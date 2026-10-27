#import "SystemMenu.h"
#import "PlayerMenuPresentation.h"
#import "../Runtime/Preferences.h"
#import "../Runtime/Localization.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>
NSNotificationName const YTKACEPlayerMenuWillSelectAction = @"YTKACEPlayerMenuWillSelectAction";
NSNotificationName const YTKACEPlayerMenuTouchSource = @"YTKACEPlayerMenuTouchSource";

// Match the rendered glyph, not its private asset name or the row's position.
// Only a right chevron is recolored; switches, checkmarks and leading icons stay native.
static BOOL DisclosureImage(UIImage *image) {
    if (!image) return NO;
    static char key;
    NSNumber *cached = objc_getAssociatedObject(image,&key);
    if (cached) return cached.boolValue;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1; format.opaque = NO;
    CGFloat scale = 32 / MAX(1,MAX(image.size.width,image.size.height));
    CGRect draw = CGRectMake((32 - image.size.width * scale) / 2,(32 - image.size.height * scale) / 2,
        image.size.width * scale,image.size.height * scale);
    UIImage *raster = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(32,32) format:format]
        imageWithActions:^(__unused UIGraphicsImageRendererContext *context) { [image drawInRect:draw]; }];
    uint8_t pixels[32 * 32 * 4] = {};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap = CGBitmapContextCreate(pixels,32,32,8,128,space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!bitmap || !raster.CGImage) { if (bitmap) CGContextRelease(bitmap); return NO; }
    CGContextDrawImage(bitmap,CGRectMake(0,0,32,32),raster.CGImage); CGContextRelease(bitmap);
    NSInteger left = 32, right = -1, top = 32, bottom = -1;
    for (NSInteger y = 0; y < 32; y++) for (NSInteger x = 0; x < 32; x++)
        if (pixels[(y * 32 + x) * 4 + 3] > 40) {
            left = MIN(left,x); right = MAX(right,x); top = MIN(top,y); bottom = MAX(bottom,y);
        }
    double sum[3] = {}, count[3] = {};
    for (NSInteger y = top; y <= bottom; y++) for (NSInteger x = left; x <= right; x++) {
        if (pixels[(y * 32 + x) * 4 + 3] <= 40) continue;
        double fraction = (double)(y - top) / MAX(1,bottom - top);
        NSInteger band = fraction < .25 ? 0 : (fraction > .75 ? 2 : (fraction > .4 && fraction < .6 ? 1 : -1));
        if (band >= 0) { sum[band] += x; count[band]++; }
    }
    double width = right - left + 1, height = bottom - top + 1;
    BOOL chevron = height >= 8 && width >= 3 && width < height * .85 && count[0] && count[1] && count[2] &&
        sum[1] / count[1] - sum[0] / count[0] > width * .25 &&
        sum[1] / count[1] - sum[2] / count[2] > width * .25 &&
        fabs(sum[0] / count[0] - sum[2] / count[2]) < width * .25;
    objc_setAssociatedObject(image,&key,@(chevron),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return chevron;
}

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
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *disclosures;
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
        _disclosureColor = UIColor.secondaryLabelColor;
        _disclosures = [NSMutableArray array];
        NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObject:view];
        for (NSUInteger i = 0; i < views.count && i < 64; i++) {
            UIView *candidate = views[i];
            if ([candidate isKindOfClass:UIImageView.class]) {
                UIImageView *icon = (id)candidate;
                CGRect frame = [icon convertRect:icon.bounds toView:view];
                if (CGRectGetMidX(frame) > view.bounds.size.width * .7 &&
                    frame.size.width <= 32 && frame.size.height <= 40 && DisclosureImage(icon.image))
                    [_disclosures addObject:@{@"view":icon,@"image":icon.image,@"tint":icon.tintColor ?: UIColor.labelColor,
                        @"alpha":@(icon.alpha),@"adjustment":@(icon.tintAdjustmentMode)}];
            }
            // Do not traverse the implementation views of native switches/buttons.
            if (candidate != view && [candidate isKindOfClass:UIControl.class]) continue;
            for (UIView *child in candidate.subviews) if (views.count < 64) [views addObject:child];
        }
        // AsyncDisplayKit can render the accessory in an image layer without
        // creating a UIImageView. Apply the same bounded glyph check there.
        NSMutableSet<CALayer *> *imageLayers = [NSMutableSet set];
        for (UIView *candidate in views) if ([candidate isKindOfClass:UIImageView.class]) [imageLayers addObject:candidate.layer];
        NSMutableArray<CALayer *> *layers = [NSMutableArray arrayWithObject:view.layer];
        for (NSUInteger i = 0; i < layers.count && i < 64; i++) {
            CALayer *layer = layers[i];
            CGRect frame = [layer convertRect:layer.bounds toLayer:view.layer];
            id contents = layer.contents;
            if (![imageLayers containsObject:layer] && contents && CGRectGetMidX(frame) > view.bounds.size.width * .7 &&
                frame.size.width <= 32 && frame.size.height <= 40 &&
                CFGetTypeID((__bridge CFTypeRef)contents) == CGImageGetTypeID()) {
                UIImage *image = [UIImage imageWithCGImage:(__bridge CGImageRef)contents scale:MAX(1,layer.contentsScale) orientation:UIImageOrientationUp];
                if (DisclosureImage(image)) [_disclosures addObject:@{@"layer":layer,@"contents":contents,@"image":image,@"opacity":@(layer.opacity)}];
            }
            // Native control internals are excluded in both traversals.
            if ([layer.delegate isKindOfClass:UIControl.class] && layer != view.layer) continue;
            for (CALayer *child in layer.sublayers) if (layers.count < 64) [layers addObject:child];
        }
    }
    return self;
}
- (void)mountInView:(UIView *)host {
    [NSLayoutConstraint deactivateConstraints:self.constraints];
    self.mounted = YES;
    self.view.translatesAutoresizingMaskIntoConstraints = YES;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // The table restores and activates this control through one selected route.
    // Do not also deliver touches to the embedded button and dispatch it twice.
    self.view.userInteractionEnabled = NO;
    [host addSubview:self.view]; self.view.frame = host.bounds;
    [self.view setNeedsLayout]; [self.view layoutIfNeeded];
    for (NSDictionary *entry in self.disclosures) {
        UIImageView *icon = entry[@"view"];
        if (icon) {
            icon.image = [entry[@"image"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            icon.tintColor = self.disclosureColor;
            icon.alpha = 1; icon.tintAdjustmentMode = UIViewTintAdjustmentModeNormal;
        } else {
            UIImage *original = entry[@"image"];
            UIImage *tinted = [original imageWithTintColor:self.disclosureColor renderingMode:UIImageRenderingModeAlwaysOriginal];
            UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
            format.scale = original.scale; format.opaque = NO;
            // UIImage may keep tint in its rendering configuration rather than
            // its CGImage. Flatten it before assigning raw CALayer contents.
            UIImage *raster = [[[UIGraphicsImageRenderer alloc] initWithSize:original.size format:format]
                imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
                    [tinted drawInRect:(CGRect){CGPointZero,original.size}];
                }];
            if (raster.CGImage) [(CALayer *)entry[@"layer"] setContents:(__bridge id)raster.CGImage];
            [(CALayer *)entry[@"layer"] setOpacity:1];
        }
    }
    if (self.disclosures.count) os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] disclosure normalized count=%lu",(unsigned long)self.disclosures.count);
}
- (void)restore {
    if (!self.mounted) return;
    self.mounted = NO;
    for (NSDictionary *entry in self.disclosures) {
        UIImageView *icon = entry[@"view"];
        if (icon) {
            icon.image = entry[@"image"]; icon.tintColor = entry[@"tint"];
            icon.alpha = [entry[@"alpha"] doubleValue];
            icon.tintAdjustmentMode = (UIViewTintAdjustmentMode)[entry[@"adjustment"] integerValue];
        } else {
            [(CALayer *)entry[@"layer"] setContents:entry[@"contents"]];
            [(CALayer *)entry[@"layer"] setOpacity:[entry[@"opacity"] floatValue]];
        }
    }
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

static char MenuTransitionKey;
@interface YTKACEMenuTransition : NSObject
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, weak) UIView *source;
@property(nonatomic, strong) UIView *cover, *snapshot;
@property(nonatomic) BOOL receivedChild;
@property(nonatomic) CGRect windowBounds;
@end
@implementation YTKACEMenuTransition @end

static void RemoveMenuTransition(YTKACEMenuTransition *transition) {
    if (!transition) return;
    [transition.cover removeFromSuperview];
    if (objc_getAssociatedObject(transition.window,&MenuTransitionKey) == transition)
        objc_setAssociatedObject(transition.window,&MenuTransitionKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
void YTKACECancelSystemMenuTransition(UIView *source) {
    YTKACEMenuTransition *transition = objc_getAssociatedObject(source.window,&MenuTransitionKey);
    if (transition.source == source) RemoveMenuTransition(transition);
}
void YTKACEContinueSystemMenuTransition(UIView *source) {
    YTKACEMenuTransition *transition = objc_getAssociatedObject(source.window,&MenuTransitionKey);
    if (transition.source == source) transition.receivedChild = YES;
}
static void BeginMenuTransition(UIViewController *menu) {
    UIWindow *window = menu.view.window;
    UIView *source = YTKACEPlayerMenuSource(menu);
    if (!window || !source || !YTKACEIsNativeGearMenuSource(source)) return;
    YTKACEMenuTransition *previous = objc_getAssociatedObject(window,&MenuTransitionKey);
    RemoveMenuTransition(previous);
    UIView *container = menu.presentationController.containerView;
    CGRect rect = [menu.view convertRect:menu.view.bounds toView:container];
    UIView *snapshot = [container resizableSnapshotViewFromRect:rect afterScreenUpdates:NO withCapInsets:UIEdgeInsetsZero];
    if (!snapshot || CGRectIsEmpty(rect)) return;
    YTKACEMenuTransition *transition = [YTKACEMenuTransition new];
    transition.window = window; transition.windowBounds = window.bounds;
    transition.source = source; transition.snapshot = snapshot;
    UIView *cover = [[UIView alloc] initWithFrame:[menu.view convertRect:menu.view.bounds toView:window]];
    cover.accessibilityIdentifier = @"YTKACE.SubmenuTransition";
    cover.accessibilityElementsHidden = YES;
    cover.userInteractionEnabled = NO; cover.clipsToBounds = YES;
    cover.layer.cornerRadius = 28; cover.layer.cornerCurve = kCACornerCurveContinuous;
    snapshot.frame = cover.bounds; snapshot.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [cover addSubview:snapshot]; [window addSubview:cover]; transition.cover = cover;
    objc_setAssociatedObject(window,&MenuTransitionKey,transition,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] submenu transition=waiting");
    // Leaf commands need no new menu. Never leave a frozen menu above the player.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350 * NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if (objc_getAssociatedObject(window,&MenuTransitionKey) != transition || transition.receivedChild) return;
        RemoveMenuTransition(transition);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2 * NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if (objc_getAssociatedObject(window,&MenuTransitionKey) == transition) {
            os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] submenu transition=expired");
            RemoveMenuTransition(transition);
        }
    });
}

static void CompleteMenuTransition(UIViewController *menu, UIView *content) {
    UIWindow *window = menu.view.window;
    YTKACEMenuTransition *transition = objc_getAssociatedObject(window,&MenuTransitionKey);
    if (!transition || transition.source != YTKACEPlayerMenuSource(menu)) return;
    if (!CGRectEqualToRect(transition.windowBounds,window.bounds)) { RemoveMenuTransition(transition); return; }
    objc_setAssociatedObject(window,&MenuTransitionKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGRect target = [menu.view convertRect:menu.view.bounds toView:window];
    [window bringSubviewToFront:transition.cover];
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    content.alpha = 0;
    content.transform = reduceMotion ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(32,0);
    menu.view.userInteractionEnabled = NO;
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] submenu transition=content-slide reduceMotion=%d",reduceMotion);
    [UIView animateWithDuration:reduceMotion ? .15 : .25 delay:0
        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
            transition.cover.frame = target;
            transition.snapshot.alpha = 0;
            transition.snapshot.transform = reduceMotion ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(-32,0);
            content.alpha = 1; content.transform = CGAffineTransformIdentity;
        } completion:^(__unused BOOL finished) {
            menu.view.userInteractionEnabled = YES; RemoveMenuTransition(transition);
        }];
}

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
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    CompleteMenuTransition(self,self.contentNavigation.view);
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
        nativeRow.disclosureColor = native.userInteractionEnabled ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
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
        if (DisclosureImage(secondary.image)) {
            secondary.image = [secondary.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            secondary.tintColor = action[@"enabled"] && ![action[@"enabled"] boolValue] ?
                UIColor.tertiaryLabelColor : UIColor.secondaryLabelColor;
        }
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
    dispatch_block_t diagnostic = action[@"diagnosticSelection"];
    if (diagnostic) diagnostic();
    BOOL (^submenuTransition)(void) = action[@"submenuTransition"];
    if (submenuTransition && submenuTransition()) BeginMenuTransition(self.menuPresentation);
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
    YTKACEMenuTransition *transition = objc_getAssociatedObject(presenter.view.window,&MenuTransitionKey);
    BOOL continuing = transition && transition.source == source;
    [presenter presentViewController:presentation animated:!continuing completion:nil];
    return YES;
}
