#import "YTKACETelemetryAuditController.h"
#import "YTKACERootOptionsController.h"
#import "../Runtime/Localization.h"
#import "../Runtime/Preferences.h"
#import "../Runtime/TelemetryAudit.h"
#import "../UI/Notice.h"

static NSString *AuditString(NSDictionary *record, NSString *key) {
    id value = record[key];
    return [value isKindOfClass:NSString.class] ? value : @"";
}
static NSString *AuditDetailText(NSDictionary *record) {
    NSMutableDictionary *metadata = [record mutableCopy];
    NSString *body = AuditString(record, @"bodyPreview");
    [metadata removeObjectForKey:@"bodyPreview"];
    NSData *data = [NSJSONSerialization dataWithJSONObject:metadata
        options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    NSString *note = [record[@"detailsCaptured"] boolValue]
        ? YTKACELocalized(@"Values are redacted. This is a request preview, not a response or packet capture.")
        : YTKACELocalized(@"This record contains metadata only. Enable request details to inspect future requests; old contents cannot be recovered.");
    if (body.length) return [NSString stringWithFormat:@"%@\n\n%@\n\n%@\n%@", note, text,
        YTKACELocalized(@"JSON Body Preview"), body];
    return [NSString stringWithFormat:@"%@\n\n%@", note, text];
}

@interface YTKACEAuditRequestDetail : UIViewController
@property(nonatomic, copy) NSDictionary *record;
@end
@implementation YTKACEAuditRequestDetail
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = YTKACELocalized(@"Request Details");
    UITextView *text = [[UITextView alloc] initWithFrame:CGRectZero];
    text.editable = NO;
    text.selectable = YES;
    text.dataDetectorTypes = UIDataDetectorTypeNone;
    text.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular]];
    text.adjustsFontForContentSizeCategory = YES;
    text.textContainerInset = UIEdgeInsetsMake(16, 16, 24, 16);
    text.text = AuditDetailText(self.record);
    self.view = text;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"doc.on.doc"] style:UIBarButtonItemStylePlain
        target:self action:@selector(copyRequest)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = YTKACELocalized(@"Copy Request");
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    YTKACEApplyAppearance(self);
    self.view.backgroundColor = YTKACEInterfaceBackgroundColor(self.traitCollection);
    ((UITextView *)self.view).textColor = UIColor.labelColor;
}
- (void)copyRequest {
    UIPasteboard.generalPasteboard.string = AuditDetailText(self.record);
    YTKACEShowNotice(YTKACELocalized(@"Request copied"));
}
@end

@interface YTKACEAuditRequests : UITableViewController <UISearchResultsUpdating>
@property(nonatomic, copy) NSArray<NSDictionary *> *records;
@property(nonatomic, copy) NSArray<NSDictionary *> *filtered;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) BOOL loading;
@end
@implementation YTKACEAuditRequests
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = YTKACELocalized(@"Observed Requests");
    self.records = @[];
    self.filtered = @[];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72;
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = YTKACELocalized(@"Search host, method, service, or path");
    self.navigationItem.searchController = self.search;
    self.definesPresentationContext = YES;
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    YTKACEApplyAppearance(self);
    self.tableView.backgroundColor = YTKACEInterfaceBackgroundColor(self.traitCollection);
    [self refresh];
    __weak __typeof__(self) weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(__unused NSTimer *timer) {
        YTKACEAuditRequests *strong = weakSelf;
        if (!strong.tableView.isTracking && !strong.tableView.isDecelerating &&
            strong.tableView.contentOffset.y <= -strong.tableView.adjustedContentInset.top + 8) [strong refresh];
    }];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.timer invalidate];
    self.timer = nil;
}
- (void)refresh {
    if (self.loading) return;
    self.loading = YES;
    __weak __typeof__(self) weakSelf = self;
    YTKACELoadTelemetryAuditRecords(^(NSArray<NSDictionary *> *records) {
        YTKACEAuditRequests *strong = weakSelf;
        if (!strong) return;
        strong.loading = NO;
        [strong.refreshControl endRefreshing];
        NSArray *ordered = records.reverseObjectEnumerator.allObjects;
        if (![ordered isEqual:strong.records]) {
            strong.records = ordered;
            [strong updateSearchResultsForSearchController:strong.search];
        } else if (!strong.records.count) [strong updateSearchResultsForSearchController:strong.search];
    });
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = [searchController.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if (!query.length) self.filtered = self.records;
    else {
        NSMutableArray *matches = [NSMutableArray array];
        for (NSDictionary *record in self.records) {
            NSString *text = [NSString stringWithFormat:@"%@ %@ %@ %@ %@",
                AuditString(record, @"host"), AuditString(record, @"method"), AuditString(record, @"service"),
                AuditString(record, @"pathPreview"), AuditString(record, @"timestamp")];
            if ([text rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound)
                [matches addObject:record];
        }
        self.filtered = matches;
    }
    if (!self.filtered.count) {
        UILabel *empty = [UILabel new];
        empty.text = YTKACELocalized(query.length ? @"No matching requests" : @"No requests observed yet. Enable recording, then use YouTube. Only observed NSURLSession requests appear.");
        empty.numberOfLines = 0;
        empty.textAlignment = NSTextAlignmentCenter;
        empty.textColor = UIColor.secondaryLabelColor;
        empty.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        self.tableView.backgroundView = empty;
    } else self.tableView.backgroundView = nil;
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; return self.filtered.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Audit.Request"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Audit.Request"];
    NSDictionary *record = self.filtered[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%@  %@", AuditString(record, @"method"), AuditString(record, @"host")];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@  %@", AuditString(record, @"timestamp"),
        AuditString(record, @"service"), AuditString(record, @"pathPreview")];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.backgroundColor = YTKACEInterfaceSurfaceColor(self.traitCollection);
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    YTKACEAuditRequestDetail *detail = [YTKACEAuditRequestDetail new];
    detail.record = self.filtered[indexPath.row];
    [self.navigationController pushViewController:detail animated:YES];
}
@end

@interface YTKACETelemetryAuditController : UITableViewController
@property(nonatomic) NSUInteger recordCount;
@property(nonatomic) BOOL preparing;
@property(nonatomic, strong) NSTimer *timer;
@end
@implementation YTKACETelemetryAuditController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = YTKACELocalized(@"Telemetry Audit");
    self.tableView.cellLayoutMarginsFollowReadableWidth = NO;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    YTKACEApplyAppearance(self);
    self.tableView.backgroundColor = YTKACEInterfaceBackgroundColor(self.traitCollection);
    [self refreshCount];
    __weak __typeof__(self) weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(__unused NSTimer *timer) { [weakSelf refreshCount]; }];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.timer invalidate];
    self.timer = nil;
}
- (void)refreshCount {
    __weak __typeof__(self) weakSelf = self;
    YTKACELoadTelemetryAuditRecords(^(NSArray<NSDictionary *> *records) {
        YTKACETelemetryAuditController *strong = weakSelf;
        if (!strong || strong.recordCount == records.count) return;
        strong.recordCount = records.count;
        if (strong.isViewLoaded) [strong.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; return section == 1 ? 1 : 2;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return YTKACELocalized(@[@"RECORDING", @"REQUESTS", @"REPORT", @"DATA"][section]);
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return YTKACELocalized(@"Metadata only by default. Request details add redacted URL/header fields and bounded JSON previews for new requests. Cookies, authorization and unknown values are masked. Streams are not consumed; binary bodies are not decoded or saved.");
    if (section == 1) return YTKACELocalized(@"Newest first; refreshes every 2 seconds at the top of the list. The rolling log keeps up to 768 KB. Only NSURLSession requests at resume are observed; later headers, redirects, other stacks and responses may be missing.");
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Audit.Option"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Audit.Option"];
    cell.backgroundColor = YTKACEInterfaceSurfaceColor(self.traitCollection);
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.text = nil;
    cell.imageView.image = nil;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if (indexPath.section == 0) {
        BOOL details = indexPath.row == 1;
        cell.textLabel.text = YTKACELocalized(details ? @"Capture Request Details" : @"Record outbound requests");
        UISwitch *toggle = [UISwitch new];
        toggle.tag = indexPath.row;
        toggle.on = details ? YTKACETelemetryAuditDetailsEnabled() : YTKACETelemetryAuditEnabled();
        [toggle addTarget:self action:@selector(recordingChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 1) {
        cell.textLabel.text = YTKACELocalized(@"Observed Requests");
        cell.detailTextLabel.text = [NSString stringWithFormat:YTKACELocalized(@"%lu observed requests"), (unsigned long)self.recordCount];
        cell.imageView.image = [UIImage systemImageNamed:@"list.bullet"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 2) {
        cell.textLabel.text = YTKACELocalized(indexPath.row == 0 ? @"Export Report" : @"Copy Report");
        cell.imageView.image = [UIImage systemImageNamed:indexPath.row == 0 ? @"square.and.arrow.up" : @"doc.on.doc"];
    } else if (indexPath.row == 0) {
        cell.textLabel.text = YTKACELocalized(@"Clear Recorded Data");
        cell.textLabel.textColor = UIColor.systemRedColor;
        cell.imageView.image = [UIImage systemImageNamed:@"trash"];
    } else {
        cell.textLabel.text = YTKACELocalized(@"Audit Coverage");
        cell.detailTextLabel.text = YTKACELocalized(@"Only NSURLSession traffic is observed");
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    cell.imageView.tintColor = cell.textLabel.textColor;
    return cell;
}
- (void)recordingChanged:(UISwitch *)sender {
    if (sender.tag == 1) YTKACESetTelemetryAuditDetailsEnabled(sender.on);
    else YTKACESetTelemetryAuditEnabled(sender.on);
}
- (void)prepareReport:(BOOL)exportFiles source:(UIView *)source {
    if (self.preparing) return;
    self.preparing = YES;
    __weak __typeof__(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *text = YTKACETelemetryAuditReportText();
        NSMutableArray *files = [NSMutableArray array];
        NSError *error = nil;
        NSURL *directory = exportFiles ? [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES] : nil;
        if (exportFiles) {
            if ([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
                NSURL *txt = [directory URLByAppendingPathComponent:@"ytkace-telemetry-audit.txt"];
                NSURL *json = [directory URLByAppendingPathComponent:@"ytkace-telemetry-audit.json"];
                if ([text writeToURL:txt atomically:YES encoding:NSUTF8StringEncoding error:&error] &&
                    [YTKACETelemetryAuditReportJSON() writeToURL:json options:NSDataWritingAtomic error:&error]) [files addObjectsFromArray:@[txt, json]];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            YTKACETelemetryAuditController *strong = weakSelf;
            if (!strong) {
                if (directory) [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
                return;
            }
            strong.preparing = NO;
            if (!strong.view.window) {
                if (directory) [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
                return;
            }
            if (!exportFiles) {
                UIPasteboard.generalPasteboard.string = text;
                YTKACEShowNotice(YTKACELocalized(@"Telemetry report copied"));
            } else if (files.count == 2) {
                UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:files applicationActivities:nil];
                share.popoverPresentationController.sourceView = source.window ? source : strong.view;
                share.popoverPresentationController.sourceRect = share.popoverPresentationController.sourceView.bounds;
                share.completionWithItemsHandler = ^(__unused UIActivityType activity, __unused BOOL completed, __unused NSArray *returned, __unused NSError *shareError) {
                    [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
                };
                [strong presentViewController:share animated:YES completion:nil];
            } else {
                if (directory) [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
                YTKACEShowNotice(YTKACELocalized(@"Could not prepare telemetry report"));
            }
        });
    });
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) [self.navigationController pushViewController:[YTKACEAuditRequests new] animated:YES];
    else if (indexPath.section == 2) [self prepareReport:indexPath.row == 0 source:[tableView cellForRowAtIndexPath:indexPath]];
    else if (indexPath.section == 3 && indexPath.row == 0) {
        __weak __typeof__(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            YTKACEClearTelemetryAudit();
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf refreshCount]; });
        });
    }
}
@end

UIViewController *YTKACEMakeTelemetryAuditController(void) { return [YTKACETelemetryAuditController new]; }
