#import "SystemMenu.h"
#import "PlayerMenuPresentation.h"
#import "../Runtime/Preferences.h"
#import "../Runtime/Localization.h"
#import <objc/message.h>
NSNotificationName const YTKACEPlayerMenuWillSelectAction = @"YTKACEPlayerMenuWillSelectAction";
NSNotificationName const YTKACEPlayerMenuTouchSource = @"YTKACEPlayerMenuTouchSource";

@interface YTKACEMenuNativeRow ()
@property(nonatomic, strong) UIView *view;
@property(nonatomic) CGFloat height;
@property(nonatomic, weak) UIView *parent;
@property(nonatomic) NSUInteger index;
@property(nonatomic) CGRect frame;
@property(nonatomic) UIViewAutoresizing resizing;
@property(nonatomic) BOOL translates;
@property(nonatomic) BOOL interaction;
@property(nonatomic) BOOL mounted;
@property(nonatomic, copy) NSArray<NSLayoutConstraint *> *constraints;
@end
@implementation YTKACEMenuNativeRow
- (instancetype)initWithView:(UIView *)view {
    if (!view.superview || !view.window || view.hidden || view.alpha < 0.05 ||
        !CGAffineTransformIsIdentity(view.transform) ||
        !isfinite(view.bounds.size.width) || !isfinite(view.bounds.size.height) ||
        view.bounds.size.width < 44 || view.bounds.size.height < 24 || view.bounds.size.height > 240) return nil;
    for (UIView *ancestor = view.superview; ancestor; ancestor = ancestor.superview)
        if (ancestor.hidden || ancestor.alpha < 0.05) return nil;
    if ((self = [super init])) {
        _view = view; _height = MAX(44,view.bounds.size.height); _parent = view.superview;
        _index = [view.superview.subviews indexOfObjectIdenticalTo:view]; _frame = view.frame;
        _resizing = view.autoresizingMask; _translates = view.translatesAutoresizingMaskIntoConstraints;
        _interaction = view.userInteractionEnabled;
        NSMutableArray *constraints = [NSMutableArray array];
        for (NSLayoutConstraint *constraint in view.constraints)
            if (constraint.active && constraint.firstItem == view && !constraint.secondItem)
                [constraints addObject:constraint];
        UIView *ancestor = view.superview;
        for (NSUInteger depth = 0; ancestor && depth < 24; ++depth, ancestor = ancestor.superview)
            for (NSLayoutConstraint *constraint in ancestor.constraints)
                if (constraint.active && (constraint.firstItem == view || constraint.secondItem == view))
                    [constraints addObject:constraint];
        _constraints = constraints;
    }
    return self;
}
- (void)mountInView:(UIView *)host {
    [NSLayoutConstraint deactivateConstraints:self.constraints];
    self.mounted = YES;
    self.view.translatesAutoresizingMaskIntoConstraints = YES;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // A table tap invokes the native block after both menus close. Do not also
    // dispatch the embedded button's target/action through a second path.
    self.view.userInteractionEnabled = NO;
    [host addSubview:self.view]; self.view.frame = host.bounds;
    [self.view setNeedsLayout]; [self.view layoutIfNeeded];
}
- (void)restore {
    if (!self.mounted) return;
    self.mounted = NO;
    [self.view removeFromSuperview];
    UIView *parent = self.parent;
    if (parent) [parent insertSubview:self.view atIndex:MIN(self.index,parent.subviews.count)];
    self.view.translatesAutoresizingMaskIntoConstraints = self.translates;
    self.view.autoresizingMask = self.resizing; self.view.frame = self.frame;
    self.view.userInteractionEnabled = self.interaction;
    for (NSLayoutConstraint *constraint in self.constraints) {
        id first = constraint.firstItem, second = constraint.secondItem;
        UIView *a = [first isKindOfClass:UILayoutGuide.class] ? [first owningView] : first;
        UIView *b = [second isKindOfClass:UILayoutGuide.class] ? [second owningView] : second;
        if (!parent || ![a isKindOfClass:UIView.class]) continue;
        if (!second) { constraint.active = YES; continue; }
        if (![b isKindOfClass:UIView.class]) continue;
        for (UIView *common = a; common; common = common.superview)
            if (b == common || [b isDescendantOfView:common]) { constraint.active = YES; break; }
    }
}
@end

@interface YTKACENativeRowCell : UITableViewCell
@property(nonatomic, strong) YTKACEMenuNativeRow *nativeRow;
@end
@implementation YTKACENativeRowCell
- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.nativeRow.view.superview == self.contentView) self.nativeRow.view.frame = self.contentView.bounds;
}
@end

@interface YTKACEMenuPresentation : UIViewController
@property(nonatomic, strong) UINavigationController *contentNavigation;
@property(nonatomic, copy) void (^dismissalHandler)(BOOL);
@property(nonatomic) BOOL selectedAction;
@property(nonatomic) BOOL notifiedDismissal;
- (void)notifyDismissal;
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
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // A popover dismissed by tapping outside does not use our close action.
    // Wait for UIKit to detach it before closing an adapted native parent.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.presentingViewController) [self notifyDismissal];
    });
}
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion {
    [super dismissViewControllerAnimated:animated completion:^{
        [self notifyDismissal];
        if (completion) completion();
    }];
}
- (void)notifyDismissal {
    if (self.notifiedDismissal) return;
    self.notifiedDismissal = YES;
    void (^handler)(BOOL) = self.dismissalHandler;
    self.dismissalHandler = nil;
    if (handler) handler(self.selectedAction);
}
@end

void YTKACENotifySystemMenuDismissed(UIViewController *menu) {
    if ([menu isKindOfClass:YTKACEMenuPresentation.class])
        [((YTKACEMenuPresentation *)menu) notifyDismissal];
}

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
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    YTKACEMenuNativeRow *row = self.actions[indexPath.row][@"nativeRow"];
    return row ? row.height : UITableViewAutomaticDimension;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *action = self.actions[indexPath.row];
    YTKACEMenuNativeRow *nativeRow = action[@"nativeRow"];
    if (nativeRow) {
        YTKACENativeRowCell *native = [[YTKACENativeRowCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        native.nativeRow = nativeRow;
        native.backgroundColor = UIColor.clearColor;
        native.contentView.clipsToBounds = YES;
        native.userInteractionEnabled = !action[@"enabled"] || [action[@"enabled"] boolValue];
        [nativeRow mountInView:native.contentView];
        return native;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SystemMenu"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SystemMenu"];
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
    ((YTKACEMenuPresentation *)self.menuPresentation).selectedAction = YES;
    UIView *source = YTKACEPlayerMenuSource(self.menuPresentation);
    YTKACERememberPlayerMenuSource(source);
    if (source) [NSNotificationCenter.defaultCenter postNotificationName:YTKACEPlayerMenuWillSelectAction
        object:source userInfo:action];
    // Dismiss before invoking actions which may immediately open another controller.
    // One presentation animation is enough for a submenu transition.
    [self.menuPresentation dismissViewControllerAnimated:NO completion:^{ if (handler) handler(); }];
}
@end

BOOL YTKACEPresentSystemMenu(UIViewController *presenter, UIView *source,
                             NSString *title, NSString *subtitle,
                             NSArray<NSDictionary *> *actions) {
    return YTKACEPresentSystemMenuWithDismissal(presenter,source,title,subtitle,actions,nil);
}

BOOL YTKACEPresentSystemMenuWithDismissal(UIViewController *presenter, UIView *source,
                             NSString *title, NSString *subtitle,
                             NSArray<NSDictionary *> *actions, void (^handler)(BOOL)) {
    if (![presenter isKindOfClass:UIViewController.class] ||
        !YTKACEFeatureEnabled(@"YTKACE.Preference.Interface.SystemMenus") ||
        !presenter.view.window || presenter.presentedViewController || actions.count == 0) return NO;
    for (NSDictionary *action in actions) {
        BOOL nativeRow = [action[@"nativeRow"] isKindOfClass:YTKACEMenuNativeRow.class];
        if (!nativeRow && (![action[@"title"] isKindOfClass:NSString.class] || ![action[@"title"] length])) return NO;
    }
    YTKACESystemMenuController *controller = [YTKACESystemMenuController new];
    controller.title = title.length ? title : YTKACELocalized(@"Options");
    controller.menuSubtitle = subtitle;
    controller.actions = actions;
    controller.playerPopover = YTKACEIsPlayerMenuSource(source);
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    navigation.view.backgroundColor = UIColor.clearColor;
    YTKACEMenuPresentation *presentation = [YTKACEMenuPresentation new];
    presentation.dismissalHandler = handler;
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
        sheet.prefersEdgeAttachedInCompactHeight = YES;
        sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = YES;
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
