#import "SystemMenu.h"
#import "PlayerMenuPresentation.h"
#import "../Runtime/Preferences.h"
#import "../Runtime/Localization.h"
#import <objc/message.h>
@interface YTKACEMenuPresentation : UIViewController
@property(nonatomic, strong) UINavigationController *contentNavigation;
@end
@implementation YTKACEMenuPresentation
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    UINavigationController *navigation = self.contentNavigation;
    [self addChildViewController:navigation];
    navigation.view.frame = self.view.bounds;
    navigation.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:navigation.view];
    [navigation didMoveToParentViewController:self];
}
@end

@class YTKACESystemMenuController;
@interface YTKACESystemMenuTable : UITableView
@property(nonatomic, weak) YTKACESystemMenuController *menuOwner;
@end

@interface YTKACESystemMenuController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, weak) UIViewController *menuPresentation;
@property(nonatomic, copy) NSArray<NSDictionary *> *actions;
@property(nonatomic, copy) NSString *menuSubtitle;
@property(nonatomic) BOOL playerPopover;
@property(nonatomic) BOOL heightUpdatePending;
@property(nonatomic) BOOL updatingSize;
- (void)updateMenuHeight;
@end

@implementation YTKACESystemMenuTable
- (void)layoutSubviews {
    [super layoutSubviews];
    // UITableView finalizes automatic row heights after its parent controller's
    // layout callback. Measure after the table's own layout, not its estimates.
    [self.menuOwner updateMenuHeight];
}
@end

@implementation YTKACESystemMenuController
- (void)loadView {
    YTKACESystemMenuTable *table = [[YTKACESystemMenuTable alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    table.menuOwner = self;
    table.delegate = self;
    table.dataSource = self;
    self.tableView = table;
    self.view = table;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60.0;
    self.tableView.estimatedSectionHeaderHeight = 0;
    self.tableView.estimatedSectionFooterHeight = 0;
    self.edgesForExtendedLayout = UIRectEdgeNone;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.tableView.contentInset = UIEdgeInsetsMake(8,0,8,0);
    self.tableView.sectionFooterHeight = CGFLOAT_MIN;
    if (@available(iOS 15.0, *)) self.tableView.sectionHeaderTopPadding = 0;
    self.tableView.backgroundColor = self.playerPopover ? UIColor.clearColor : UIColor.systemGroupedBackgroundColor;
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    SEL factory = NSSelectorFromString(@"effectWithStyle:");
    if (!self.playerPopover && !UIAccessibilityIsReduceTransparencyEnabled() && [glassClass respondsToSelector:factory]) {
        UIVisualEffect *effect = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassClass, factory, 0);
        UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
        glass.userInteractionEnabled = NO;
        self.tableView.backgroundColor = UIColor.clearColor;
        self.tableView.backgroundView = glass;
    }
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeMenu)];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateMenuHeight];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Finish self-sizing once presentation has supplied the real table width.
    // This runs outside the layout callback, before measuring the final rows.
    [self.tableView layoutIfNeeded];
    [self updateMenuHeight];
}
- (void)updateMenuHeight {
    if (self.updatingSize || !self.view.window) return;
    self.updatingSize = YES;
    @try {
    UINavigationController *navigation = self.navigationController;
    CGRect safe = UIEdgeInsetsInsetRect(self.view.window.bounds, self.view.window.safeAreaInsets);
    CGFloat contentHeight = self.tableView.contentSize.height;
    if (self.actions.count) {
        CGRect last = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:self.actions.count - 1 inSection:0]];
        if (!CGRectIsEmpty(last) && isfinite(CGRectGetMaxY(last))) contentHeight = CGRectGetMaxY(last);
    }
    CGFloat height = MIN(MAX(88,ceil(contentHeight + self.tableView.contentInset.top +
        self.tableView.contentInset.bottom + navigation.navigationBar.bounds.size.height)),
        MAX(88.0, safe.size.height - 24));
    UIViewController *presentation = self.menuPresentation;
    CGSize size = presentation.preferredContentSize;
    if (height <= 0 || fabs(size.height - height) <= 1) return;
    CGFloat width = size.width > 0 ? size.width : 340;
    // The presentation wrapper owns the height. UINavigationController otherwise
    // adds its own preferred-size bar margins again during popover sizing.
    presentation.preferredContentSize = CGSizeMake(width,height);
    if (presentation.modalPresentationStyle == UIModalPresentationPageSheet && !self.heightUpdatePending) {
        self.heightUpdatePending = YES;
        __weak YTKACESystemMenuController *weak = self;
        // Resolve from the measured table, coalescing UIKit's layout callbacks.
        // Never force layout recursively or leave a fixed row-count-sized footer.
        dispatch_async(dispatch_get_main_queue(), ^{
            YTKACESystemMenuController *owner = weak;
            if (!owner) return;
            owner.heightUpdatePending = NO;
            if (@available(iOS 16.0, *)) [owner.menuPresentation.sheetPresentationController invalidateDetents];
        });
    }
    } @finally { self.updatingSize = NO; }
}
- (void)closeMenu { [self.menuPresentation dismissViewControllerAnimated:YES completion:nil]; }
- (BOOL)accessibilityPerformEscape { [self closeMenu]; return YES; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; return self.actions.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section; return self.menuSubtitle.length ? self.menuSubtitle : nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section; return CGFLOAT_MIN;
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.menuSubtitle.length ? UITableViewAutomaticDimension : CGFLOAT_MIN;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SystemMenu"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SystemMenu"];
    NSDictionary *action = self.actions[indexPath.row];
    cell.textLabel.text = action[@"title"];
    NSMutableArray *details = [NSMutableArray array];
    for (NSString *key in @[@"subtitle", @"value"]) {
        NSString *detail = action[key];
        if (detail.length && ![details containsObject:detail]) [details addObject:detail];
    }
    cell.detailTextLabel.text = [details componentsJoinedByString:@"\n"];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.imageView.image = action[@"icon"];
    cell.accessoryType = [action[@"selected"] boolValue] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    if (action[@"secondary"] && ![action[@"selected"] boolValue]) {
        UIImageView *secondary = [[UIImageView alloc] initWithImage:action[@"secondary"]];
        secondary.contentMode = UIViewContentModeScaleAspectFit;
        secondary.frame = CGRectMake(0, 0, 22, 22);
        cell.accessoryView = secondary;
    }
    BOOL enabled = !action[@"enabled"] || [action[@"enabled"] boolValue];
    cell.userInteractionEnabled = enabled;
    cell.textLabel.textColor = !enabled ? UIColor.tertiaryLabelColor :
        ([action[@"destructive"] boolValue] ? UIColor.systemRedColor : UIColor.labelColor);
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessibilityTraits = UIAccessibilityTraitButton | (enabled ? 0 : UIAccessibilityTraitNotEnabled) |
        ([action[@"selected"] boolValue] ? UIAccessibilityTraitSelected : 0);
    cell.backgroundColor = UIColor.clearColor;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *action = self.actions[indexPath.row];
    if (action[@"enabled"] && ![action[@"enabled"] boolValue]) return;
    dispatch_block_t handler = action[@"handler"];
    YTKACERememberPlayerMenuSource(self.menuPresentation.popoverPresentationController.sourceView);
    // Dismiss before invoking actions which may immediately open another controller.
    // One presentation animation is enough for a submenu transition.
    [self.menuPresentation dismissViewControllerAnimated:NO completion:^{ if (handler) handler(); }];
}
@end

BOOL YTKACEPresentSystemMenu(UIViewController *presenter, UIView *source,
                             NSString *title, NSString *subtitle,
                             NSArray<NSDictionary *> *actions) {
    if (![presenter isKindOfClass:UIViewController.class] ||
        !YTKACEFeatureEnabled(@"YTKACE.Preference.Interface.SystemMenus") ||
        !presenter.view.window || presenter.presentedViewController || actions.count == 0) return NO;
    for (NSDictionary *action in actions) {
        if (![action[@"title"] isKindOfClass:NSString.class] || ![action[@"title"] length]) return NO;
    }
    YTKACESystemMenuController *controller = [YTKACESystemMenuController new];
    controller.title = title.length ? title : YTKACELocalized(@"Options");
    controller.menuSubtitle = subtitle;
    controller.actions = actions;
    controller.playerPopover = YTKACEIsPlayerMenuSource(source) && source.window == presenter.view.window;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    navigation.view.backgroundColor = UIColor.clearColor;
    YTKACEMenuPresentation *presentation = [YTKACEMenuPresentation new];
    presentation.contentNavigation = navigation;
    controller.menuPresentation = presentation;
    presentation.modalPresentationStyle = UIModalPresentationPageSheet;
    presentation.preferredContentSize = CGSizeMake(340,100 + actions.count * 60);
    controller.playerPopover = YTKACEConfigurePlayerPopover(presentation, presenter, source,
        CGSizeMake(340.0, 100.0 + actions.count * 60.0));
    if (controller.playerPopover) {
        // The native popover supplies its own material, including Liquid Glass
        // on supported systems. Do not stack another glass layer over it.
    } else if (presenter.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        presentation.modalPresentationStyle = UIModalPresentationPopover;
        presentation.preferredContentSize = CGSizeMake(360.0, MIN(600.0, 100.0 + actions.count * 64.0));
        UIPopoverPresentationController *popover = presentation.popoverPresentationController;
        BOOL usable = source && source.window == presenter.view.window && !CGRectIsEmpty(source.bounds);
        for (UIView *view = source; usable && view; view = view.superview)
            if (view.hidden || view.alpha < 0.05) usable = NO;
        popover.sourceView = usable ? source : presenter.view;
        popover.sourceRect = popover.sourceView.bounds;
    } else {
        UISheetPresentationController *sheet = presentation.sheetPresentationController;
        sheet.prefersGrabberVisible = YES;
        sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
        if (@available(iOS 16.0, *)) {
            __weak UIViewController *weakPresentation = presentation;
            sheet.detents = @[[UISheetPresentationControllerDetent customDetentWithIdentifier:@"YTKACE.Menu"
                resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                    CGFloat measured = weakPresentation.preferredContentSize.height;
                    return MIN(MAX(88,measured), context.maximumDetentValue);
                }]];
            sheet.selectedDetentIdentifier = @"YTKACE.Menu";
        } else sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
    }
    [presenter presentViewController:presentation animated:YES completion:nil];
    return YES;
}
