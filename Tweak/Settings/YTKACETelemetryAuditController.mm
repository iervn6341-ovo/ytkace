#import "YTKACETelemetryAuditController.h"

#import "YTKACERootOptionsController.h"
#import "../Runtime/Localization.h"
#import "../Runtime/Preferences.h"
#import "../Runtime/TelemetryAudit.h"
#import "../UI/Notice.h"

@interface YTKACETelemetryAuditController : UITableViewController
@end

@implementation YTKACETelemetryAuditController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = YTKACELocalized(@"Telemetry Audit");
    self.tableView.cellLayoutMarginsFollowReadableWidth = NO;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    YTKACEApplyAppearance(self);
    self.tableView.backgroundColor = YTKACEInterfaceBackgroundColor(self.traitCollection);
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? 1 : 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return @[
        YTKACELocalized(@"RECORDING"),
        YTKACELocalized(@"REPORT"),
        YTKACELocalized(@"DATA")
    ][(NSUInteger)section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section != 0) return nil;
    return YTKACELocalized(@"Records only outbound NSURLSession metadata. URLs, query values, cookies, credentials, header values, and request bodies are excluded. Other networking stacks may not be visible.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCellStyle style = indexPath.section == 1 && indexPath.row == 0
        ? UITableViewCellStyleSubtitle : UITableViewCellStyleDefault;
    NSString *identifier = [NSString stringWithFormat:@"YTKACETelemetry-%ld", (long)style];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:identifier];
    cell.backgroundColor = YTKACEInterfaceBackgroundColor(self.traitCollection);
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (indexPath.section == 0) {
        cell.textLabel.text = YTKACELocalized(@"Record outbound requests");
        UISwitch *toggle = [UISwitch new];
        toggle.on = YTKACETelemetryAuditEnabled();
        [toggle addTarget:self action:@selector(recordingChanged:)
          forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 1 && indexPath.row == 0) {
        cell.textLabel.text = YTKACELocalized(@"Export Report");
        cell.detailTextLabel.text = [NSString stringWithFormat:YTKACELocalized(@"%lu observed requests"),
            (unsigned long)YTKACETelemetryAuditRecordCount()];
        cell.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.up"];
    } else if (indexPath.section == 1) {
        cell.textLabel.text = YTKACELocalized(@"Copy Report");
        cell.imageView.image = [UIImage systemImageNamed:@"doc.on.doc"];
    } else if (indexPath.row == 0) {
        cell.textLabel.text = YTKACELocalized(@"Clear Recorded Data");
        cell.textLabel.textColor = UIColor.systemRedColor;
        cell.imageView.image = [UIImage systemImageNamed:@"trash"];
    } else {
        cell.textLabel.text = YTKACELocalized(@"Audit Coverage");
        cell.detailTextLabel.text = YTKACELocalized(@"Only NSURLSession traffic is observed");
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.imageView.image = [UIImage systemImageNamed:@"info.circle"];
    }
    cell.imageView.tintColor = cell.textLabel.textColor;
    return cell;
}

- (void)recordingChanged:(UISwitch *)sender {
    YTKACESetTelemetryAuditEnabled(sender.on);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && indexPath.row == 0) {
        NSURL *directory = [NSURL fileURLWithPath:NSTemporaryDirectory()
                                      isDirectory:YES];
        NSURL *textURL = [directory URLByAppendingPathComponent:@"ytkace-telemetry-audit.txt"];
        NSURL *jsonURL = [directory URLByAppendingPathComponent:@"ytkace-telemetry-audit.json"];
        NSError *error = nil;
        BOOL wroteText = [YTKACETelemetryAuditReportText()
            writeToURL:textURL atomically:YES encoding:NSUTF8StringEncoding error:&error];
        BOOL wroteJSON = [YTKACETelemetryAuditReportJSON() writeToURL:jsonURL options:0 error:&error];
        if (!wroteText || !wroteJSON) {
            YTKACEShowNotice(YTKACELocalized(@"Could not prepare telemetry report"));
            return;
        }
        UIActivityViewController *share = [[UIActivityViewController alloc]
            initWithActivityItems:@[textURL, jsonURL] applicationActivities:nil];
        share.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:indexPath];
        share.popoverPresentationController.sourceRect = [tableView cellForRowAtIndexPath:indexPath].bounds;
        [self presentViewController:share animated:YES completion:nil];
    } else if (indexPath.section == 1 && indexPath.row == 1) {
        UIPasteboard.generalPasteboard.string = YTKACETelemetryAuditReportText();
        YTKACEShowNotice(YTKACELocalized(@"Telemetry report copied"));
    } else if (indexPath.section == 2 && indexPath.row == 0) {
        YTKACEClearTelemetryAudit();
        [self.tableView reloadData];
    }
}

@end

UIViewController *YTKACEMakeTelemetryAuditController(void) {
    return [YTKACETelemetryAuditController new];
}
