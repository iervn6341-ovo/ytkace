#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import "../../Tweak/UI/SystemMenu.h"
#import "../../Tweak/UI/PlayerMenuPresentation.h"
#import "../../Tweak/UI/NativePlayerMenu.h"
#import "../../Tweak/Runtime/Preferences.h"
#import "../../Tweak/Runtime/Localization.h"
#import "../../Tweak/Features/Downloads/DownloadLog.h"
#import "../../Tweak/YTKACE.h"

static BOOL Features = YES;
NSString * const YTKACEPreferencesDidChangeNotification = @"YTKACEPreferencesDidChange";
BOOL YTKACEFeatureEnabled(NSString *key) { (void)key; return Features; }
BOOL YTKACELiquidGlassAvailable(void) { return NSClassFromString(@"UIGlassEffect") != nil; }
NSString *YTKACELocalized(NSString *key) { return key; }
void YTKACEDownloadLog(NSString *identifier, NSString *format, ...) { (void)identifier; (void)format; }
static NSString *ResultPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/result.txt"];
}
static void Check(BOOL passed, NSString *message) {
    if (passed) return;
    [[@"FAIL: " stringByAppendingString:message] writeToFile:ResultPath()
        atomically:YES encoding:NSUTF8StringEncoding error:nil];
    abort();
}
static void Later(dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), block);
}

// Stand-ins verify UIKit presentation and hook routing, not YouTube's private layout.
@interface YTMainAppControlsOverlayView : UIView @end
@implementation YTMainAppControlsOverlayView @end
@interface YTDraggableView : UIView @end
@implementation YTDraggableView @end
@interface NativeTestAction : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) id handler;
@property(nonatomic, strong) id button;
@property(nonatomic, strong) id titleText;
@end
@implementation NativeTestAction @end
static NSUInteger NativeOriginReads;
@interface NativeOriginAction : NativeTestAction @end
@implementation NativeOriginAction
- (NSString *)title { NativeOriginReads++; return nil; }
@end
// Reproduce the device's title=0/handler=1 shape: no title getter or title ivar.
@interface YTActionSheetAction : NSObject
@property(nonatomic, copy) id handler;
@property(nonatomic, strong) UIButton *button;
@property(nonatomic) NSInteger receivedStyle;
@property(nonatomic) BOOL receivedSelection;
@property(nonatomic, copy) NSString *receivedValue;
+ (instancetype)actionWithTitle:(NSString *)title iconImage:(UIImage *)icon style:(NSInteger)style handler:(id)handler;
+ (instancetype)actionWithTitle:(NSString *)title currentValue:(NSString *)value iconImage:(UIImage *)icon accessibilityIdentifier:(NSString *)identifier handler:(id)handler;
+ (instancetype)actionWithTitle:(NSString *)title subtitle:(NSString *)subtitle iconImage:(UIImage *)icon visiblySelected:(BOOL)selected accessibilityLabel:(NSString *)label accessibilityIdentifier:(NSString *)identifier handler:(id)handler;
@end
@implementation YTActionSheetAction
+ (instancetype)actionWithTitle:(NSString *)title iconImage:(UIImage *)icon style:(NSInteger)style handler:(id)handler {
    (void)title; (void)icon;
    YTActionSheetAction *action = [self new]; action.handler = handler; action.receivedStyle = style;
    return action;
}
+ (instancetype)actionWithTitle:(NSString *)title currentValue:(NSString *)value iconImage:(UIImage *)icon accessibilityIdentifier:(NSString *)identifier handler:(id)handler {
    (void)title; (void)icon; (void)identifier;
    YTActionSheetAction *action = [self new]; action.handler = handler; action.receivedValue = value;
    return action;
}
+ (instancetype)actionWithTitle:(NSString *)title subtitle:(NSString *)subtitle iconImage:(UIImage *)icon visiblySelected:(BOOL)selected accessibilityLabel:(NSString *)label accessibilityIdentifier:(NSString *)identifier handler:(id)handler {
    (void)title; (void)subtitle; (void)icon; (void)label; (void)identifier;
    YTActionSheetAction *action = [self new]; action.handler = handler; action.receivedSelection = selected;
    return action;
}
@end
@interface NativeTestFormattedText : NSObject
@property(nonatomic, copy) NSString *plain;
- (NSString *)stringWithFormattingRemoved;
@end
@implementation NativeTestFormattedText
- (NSString *)stringWithFormattingRemoved { return self.plain; }
@end
@interface YTSpacerButton : UIButton @end
@implementation YTSpacerButton @end
@interface YTMenuItemElementsMDCButton : UIControl
@property(nonatomic, strong) UIView *elementView;
@end
@implementation YTMenuItemElementsMDCButton @end
// Render pixels without exposing text/attributedText/accessibility data, just
// like the device's opaque ELM row. Its original control must remain intact.
@interface NativeTestOpaqueButton : YTMenuItemElementsMDCButton
@property(nonatomic) NSUInteger nativeTargetCalls;
- (void)nativeTap;
@end
@implementation NativeTestOpaqueButton
- (void)drawRect:(CGRect)rect {
    (void)rect;
    [@"Native element row" drawAtPoint:CGPointMake(16,16)
        withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:17],NSForegroundColorAttributeName:UIColor.labelColor}];
}
- (void)nativeTap { self.nativeTargetCalls++; }
@end
@interface NativeTestNode : NSObject
@property(nonatomic, copy) NSArray *subnodes;
@property(nonatomic, copy) NSArray *yogaChildren;
@property(nonatomic, strong) id controller;
@property(nonatomic, copy) NSAttributedString *attributedText;
@end
@implementation NativeTestNode @end
@interface NativeTestNodeController : NSObject
@property(nonatomic, copy) NSArray *children;
@property(nonatomic, strong) id materializedInstance;
@property(nonatomic, strong) id node;
@end
@implementation NativeTestNodeController @end
@interface NativeTestNodeView : UIView
@property(nonatomic, strong) NativeTestNode *keepalive_node;
@end
@implementation NativeTestNodeView @end
@interface NativeTestIndexedView : UIView
@property(nonatomic, strong) UIAccessibilityElement *virtualText;
@end
@implementation NativeTestIndexedView
- (NSInteger)accessibilityElementCount { return 1; }
- (id)accessibilityElementAtIndex:(NSInteger)index { return index == 0 ? self.virtualText : nil; }
@end
static NativeTestAction *VirtualAction(NSString *title, NSUInteger mode, dispatch_block_t handler) {
    NativeTestAction *action = [NativeTestAction new]; action.handler = handler;
    YTMenuItemElementsMDCButton *button = [YTMenuItemElementsMDCButton new]; action.button = button;
    if (mode == 0) {
        button.elementView = [UIView new];
        UIAccessibilityElement *text = [[UIAccessibilityElement alloc] initWithAccessibilityContainer:button.elementView];
        text.accessibilityLabel = title; button.elementView.accessibilityElements = @[text];
    } else if (mode == 1) {
        NativeTestNodeView *view = [NativeTestNodeView new]; button.elementView = view;
        NativeTestNode *root = [NativeTestNode new], *text = [NativeTestNode new];
        text.attributedText = [[NSAttributedString alloc] initWithString:title]; root.subnodes = @[text];
        view.keepalive_node = root;
    } else if (mode == 2) {
        NativeTestIndexedView *view = [NativeTestIndexedView new]; button.elementView = view;
        view.virtualText = [[UIAccessibilityElement alloc] initWithAccessibilityContainer:view];
        view.virtualText.accessibilityAttributedLabel = [[NSAttributedString alloc] initWithString:title];
    } else {
        NativeTestNodeView *view = [NativeTestNodeView new]; button.elementView = view;
        NativeTestNode *root = [NativeTestNode new], *text = [NativeTestNode new];
        text.attributedText = [[NSAttributedString alloc] initWithString:title];
        view.keepalive_node = root;
        if (mode == 3) root.yogaChildren = @[text];
        else {
            NativeTestNodeController *controller = [NativeTestNodeController new];
            NativeTestNodeController *child = [NativeTestNodeController new];
            NativeTestNodeController *materialized = [NativeTestNodeController new];
            root.controller = controller; controller.children = @[child];
            child.materializedInstance = materialized; materialized.node = text;
            // Match ELM's node/controller back-reference without looping forever.
            text.controller = materialized;
        }
    }
    return action;
}
@interface NativeTestRenderer : NSObject
@property(nonatomic, copy) NSString *menuItemIdentifier;
@property(nonatomic, strong) id text;
- (id)menuNavigationItemRenderer;
@end
@implementation NativeTestRenderer
- (id)menuNavigationItemRenderer { return self; }
@end
@interface NativeTestResponder : NSObject
@property(nonatomic, copy) dispatch_block_t callback;
@property(nonatomic, weak) UIView *lastSource;
- (void)didPressVideoQuality:(UIView *)source;
@end
@implementation NativeTestResponder
- (void)didPressVideoQuality:(UIView *)source { self.lastSource = source; self.callback(); }
@end
@interface YTMenuController : NSObject
@property(nonatomic, copy) NSArray *actions;
- (NSArray *)actionsForRenderers:(NSArray *)renderers fromView:(UIView *)source entry:(id)entry
                 shouldLogItems:(BOOL)logItems firstResponder:(id)responder;
@end
@implementation YTMenuController
- (NSArray *)actionsForRenderers:(NSArray *)renderers fromView:(UIView *)source entry:(id)entry
                 shouldLogItems:(BOOL)logItems firstResponder:(id)responder {
    (void)renderers; (void)source; (void)entry; (void)logItems; (void)responder; return self.actions;
}
@end
@interface YTBottomSheetController : UIViewController
@property(nonatomic, copy) NSArray *actions;
@property(nonatomic, strong) id actionsController;
@property(nonatomic, strong) UIButton *lateTitleButton;
@property(nonatomic, weak) UIView *hideSourceOnAppearance;
@end
@implementation YTBottomSheetController
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.hideSourceOnAppearance.hidden = YES;
    self.hideSourceOnAppearance.transform = CGAffineTransformMakeScale(0.01,0.01);
    [self.lateTitleButton setTitle:@"Native appearance-time title" forState:UIControlStateNormal];
}
@end
@interface NativeTestOwner : NSObject
@property(nonatomic, copy) NSArray *actions;
@property(nonatomic, weak) UIViewController *native;
@property(nonatomic) NSUInteger dismissals;
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion;
@end
@implementation NativeTestOwner
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion {
    self.dismissals++;
    [self.native dismissViewControllerAnimated:animated completion:completion];
}
@end

static NSUInteger NativePresentations, NativeDismissals;
@interface NativeTestPresentation : UIPresentationController @end
@implementation NativeTestPresentation
- (BOOL)shouldRemovePresentersView { return NO; }
- (void)presentationTransitionWillBegin { NativePresentations++; [super presentationTransitionWillBegin]; }
- (void)dismissalTransitionDidEnd:(BOOL)completed {
    if (completed) NativeDismissals++;
    [super dismissalTransitionDidEnd:completed];
}
@end

// A location fixture exercises the production gesture delegate; no HID events
// or real YouTube private views are injected by this simulator harness.
@interface NativeTestTouch : UITouch
@property(nonatomic, weak) UIView *referenceView;
@property(nonatomic) CGPoint point;
@end
@implementation NativeTestTouch
- (CGPoint)locationInView:(UIView *)view { return [self.referenceView convertPoint:self.point toView:view]; }
@end

static UINavigationController *MenuNavigation(UIViewController *presentation) {
    return [presentation isKindOfClass:UINavigationController.class] ? (id)presentation : (id)presentation.childViewControllers.firstObject;
}
@interface PlayerMenuSmoke : UIResponder <UIApplicationDelegate, UIWindowSceneDelegate, UIViewControllerTransitioningDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) UIViewController *root;
@property(nonatomic, strong) UIButton *button;
@property(nonatomic, strong) UIButton *qualityButton;
@property(nonatomic, strong) UIButton *nativeButton;
@property(nonatomic) NSUInteger nativeCompletions;
@property(nonatomic, strong) UIButton *gearButton;
@property(nonatomic, strong) YTBottomSheetController *gearNative;
@property(nonatomic, strong) YTBottomSheetController *gearChild;
@property(nonatomic) NSUInteger gearRound, gearCallbacks, gearChildCallbacks;
@property(nonatomic) CGRect gearAnchorRect;
@property(nonatomic) NSInteger callbacks;
@property(nonatomic) NSInteger nativeOpens;
@property(nonatomic, strong) UIViewController *nativeMenu;
@property(nonatomic, strong) YTBottomSheetController *adaptedNative;
@property(nonatomic) NSInteger adaptedRound;
@property(nonatomic) NSInteger adaptedCallbacks;
@property(nonatomic, strong) NativeTestResponder *nativeResponder;
@property(nonatomic, strong) NativeTestOpaqueButton *opaqueButton;
@property(nonatomic, strong) UIView *opaqueParent;
@property(nonatomic, strong) NSLayoutConstraint *opaqueWidth;
@end
@implementation PlayerMenuSmoke
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application; (void)options;
    YTKACEInstallPlayerMenuPresentation();
    return YES;
}
- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)application; (void)options;
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];
    configuration.delegateClass = self.class;
    return configuration;
}
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.root = [UIViewController new];
    self.window.rootViewController = self.root;
    self.root.view.backgroundColor = UIColor.systemIndigoColor;
    YTMainAppControlsOverlayView *overlay = [[YTMainAppControlsOverlayView alloc] initWithFrame:self.root.view.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.root.view addSubview:overlay];
    self.button = [UIButton buttonWithType:UIButtonTypeSystem];
    self.button.frame = CGRectMake(overlay.bounds.size.width - 72, 90, 44, 44);
    self.button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.button setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
    self.button.tintColor = UIColor.whiteColor;
    [overlay addSubview:self.button];
    YTKACERegisterTweakPlayerMenuSource(self.button);
    self.qualityButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.qualityButton.frame = CGRectMake(overlay.bounds.size.width - 122,90,44,44);
    self.qualityButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.qualityButton setTitle:@"Auto" forState:UIControlStateNormal];
    [overlay addSubview:self.qualityButton];
    YTKACERegisterTweakPlayerMenuSource(self.qualityButton);
    self.nativeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.nativeButton.frame = CGRectMake(20,90,44,44);
    // A spoofed identifier must not classify a native control as tweak-owned.
    self.nativeButton.accessibilityIdentifier = @"YTKACE Quality";
    [self.nativeButton setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
    [overlay addSubview:self.nativeButton];
    [self.window makeKeyAndVisible];
    UIWindowSceneGeometryPreferencesIOS *portrait = [[UIWindowSceneGeometryPreferencesIOS alloc]
        initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait];
    [self.window.windowScene requestGeometryUpdateWithPreferences:portrait errorHandler:^(NSError *error) {
        Check(NO,[@"initial portrait failed: " stringByAppendingString:error.localizedDescription]);
    }];
    Later(^{
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--preview-native-gear"]) {
            self.button.hidden = YES; self.qualityButton.hidden = YES;
            [self testGearPopover];
        } else [self testOwnedMenu];
    });
}
- (NSArray *)actions {
    __weak PlayerMenuSmoke *weak = self;
    return @[
        @{@"title": @"1080p", @"selected": @YES, @"handler": [^{ weak.callbacks++; } copy]},
        @{@"title": @"Unavailable", @"enabled": @NO},
        @{@"title": @"Sleep timer", @"subtitle": @"End of video", @"icon": [UIImage systemImageNamed:@"moon.zzz"]}
    ];
}
- (void)testOwnedMenu {
    [self testMissingActionTitles];
    UIView *clip = [[UIView alloc] initWithFrame:CGRectMake(20,140,44,44)]; clip.clipsToBounds = YES;
    UIButton *clipped = [[UIButton alloc] initWithFrame:CGRectMake(60,0,44,44)];
    YTKACERegisterTweakPlayerMenuSource(clipped);
    [clip addSubview:clipped]; [self.button.superview addSubview:clip];
    Check(!YTKACEIsPlayerMenuSource(clipped),@"a scrolled/clipped button must not anchor a popup");
    clip.clipsToBounds = NO;
    Check(YTKACEIsPlayerMenuSource(clipped),@"visible unclipped player button must be eligible");
    [clip removeFromSuperview];
    NativeTestAction *unsupported = [NativeTestAction new]; unsupported.title = @"Unsupported native control";
    unsupported.handler = @"not a block";
    YTBottomSheetController *special = [YTBottomSheetController new]; special.actions = @[unsupported];
    Check(!YTKACENativePlayerActions(special),@"unsupported handlers must keep their native sheet");
    Check(YTKACEPresentSystemMenu(self.root, self.button, @"Player options", nil, self.actions), @"owned menu did not present");
    Later(^{
        UIViewController *menu = self.root.presentedViewController;
        Check(YTKACEIsPlayerPopover(menu), @"owned menu did not stay a player popover");
        Check(menu.modalPresentationStyle == UIModalPresentationPopover, @"wrong presentation style");
        Check(menu.popoverPresentationController.sourceView == self.button, @"wrong anchor");
        Check([menu.popoverPresentationController.delegate adaptivePresentationStyleForPresentationController:menu.presentationController] == UIModalPresentationNone, @"compact-width adaptation enabled");
        CGRect frame = [menu.view convertRect:menu.view.bounds toView:self.window];
        Check(CGRectContainsRect(CGRectInset(self.window.bounds, -1, -1), frame), @"popover exceeded window");
        UITableViewController *content = (id)MenuNavigation(menu).topViewController;
        CGFloat slack = content.tableView.bounds.size.height - content.tableView.contentSize.height -
            content.tableView.contentInset.top - content.tableView.contentInset.bottom;
        Check(slack < 24, [NSString stringWithFormat:@"short player menu blank footer slack=%.1f table=%@ content=%@ preferred=%@ nav=%.1f child=%@ last=%@ safe=%@ adjusted=%@ navsafe=%@",slack,NSStringFromCGRect(content.tableView.bounds),NSStringFromCGSize(content.tableView.contentSize),NSStringFromCGSize(menu.preferredContentSize),MenuNavigation(menu).navigationBar.bounds.size.height,NSStringFromCGSize(content.preferredContentSize),NSStringFromCGRect([content.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]]),NSStringFromUIEdgeInsets(content.tableView.safeAreaInsets),NSStringFromUIEdgeInsets(content.tableView.adjustedContentInset),NSStringFromUIEdgeInsets(menu.view.safeAreaInsets)]);
        UITableViewCell *selected = [content.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        Check(selected.accessoryType == UITableViewCellAccessoryCheckmark, @"selection lost");
        [content.tableView.delegate tableView:content.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
        Check(self.callbacks == 0 && self.root.presentedViewController == menu, @"disabled action executed");
        [content.tableView.delegate tableView:content.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        Later(^{
            Check(self.callbacks == 1 && !self.root.presentedViewController, @"callback/dismissal ordering failed");
            [self testSettingsScope];
        });
    });
}
- (void)testMissingActionTitles {
    __block NSUInteger calls = 0;
    dispatch_block_t handler = ^{ calls++; };
    UIImage *icon = [UIImage systemImageNamed:@"gearshape"];
    YTActionSheetAction *factory = [YTActionSheetAction actionWithTitle:@"1080p60" iconImage:icon style:19 handler:handler];
    factory.button = [UIButton new];
    Check([YTKACENativeControlTitle(factory.button) isEqual:@"1080p60"],@"native control activation must retain a factory label even when the control title is empty");
    Check(![factory respondsToSelector:NSSelectorFromString(@"title")] && factory.receivedStyle == 19,
        @"factory capture must support absent native title getters without altering arguments");
    YTActionSheetAction *valued = [YTActionSheetAction actionWithTitle:@"Quality" currentValue:@"Auto (720p)" iconImage:icon accessibilityIdentifier:nil handler:handler];
    YTActionSheetAction *selected = [YTActionSheetAction actionWithTitle:@"2160p" subtitle:@"HDR" iconImage:icon visiblySelected:YES accessibilityLabel:nil accessibilityIdentifier:nil handler:handler];
    NativeTestAction *button = [NativeTestAction new]; button.handler = handler;
    button.button = [UIButton buttonWithType:UIButtonTypeCustom]; [button.button setTitle:@"1440p" forState:UIControlStateNormal];
    NativeTestAction *element = [NativeTestAction new]; element.handler = handler;
    element.button = [UIButton buttonWithType:UIButtonTypeCustom];
    UIView *content = [UIView new]; UILabel *label = [UILabel new]; label.text = @"Playback speed";
    [content addSubview:label]; [element.button addSubview:content];
    NativeTestAction *accessible = [NativeTestAction new]; accessible.handler = handler;
    accessible.button = [UIButton buttonWithType:UIButtonTypeCustom];
    UIView *accessibleView = [UIView new]; accessibleView.accessibilityLabel = @"Captions";
    [accessible.button addSubview:accessibleView];
    NativeTestAction *formatted = [NativeTestAction new]; formatted.handler = handler;
    NativeTestFormattedText *text = [NativeTestFormattedText new]; text.plain = @"Audio track";
    formatted.titleText = text;
    YTBottomSheetController *native = [YTBottomSheetController new];
    native.actions = @[factory,valued,selected,button,element,accessible,formatted];
    NSArray *actions = YTKACENativePlayerActions(native);
    Check(actions.count == 7,@"title-less actions must decode through factory/button/element/accessibility/formatted text");
    NSArray *titles = @[@"1080p60",@"Quality",@"2160p",@"1440p",@"Playback speed",@"Captions",@"Audio track"];
    for (NSUInteger index = 0; index < titles.count; ++index)
        Check([actions[index][@"title"] isEqual:titles[index]],@"native display text must be preserved");
    Check([actions[1][@"value"] isEqual:@"Auto (720p)"] && [valued.receivedValue isEqual:@"Auto (720p)"],@"current-value factory arguments must remain intact");
    Check([actions[2][@"selected"] boolValue] && selected.receivedSelection &&
        [actions[2][@"subtitle"] isEqual:@"HDR"] && actions[2][@"icon"] == icon,@"selected/subtitle/icon metadata must survive missing getters");
    Check(calls == 0,@"reading menu labels must never execute actions");
    ((dispatch_block_t)actions[0][@"handler"])();
    Check(calls == 1,@"captured actions must keep the original handler exactly once");
    NativeTestAction *pending = [NativeTestAction new]; pending.handler = handler;
    pending.button = [UIButton buttonWithType:UIButtonTypeCustom]; native.actions = @[pending];
    Check(!YTKACENativePlayerActions(native) && YTKACENativeMenuNeedsTextRetry(native),@"appearance-time labels must request one post-presentation retry");
    [pending.button setTitle:@"Ready after appearance" forState:UIControlStateNormal];
    Check(YTKACENativePlayerActions(native).count == 1 && !YTKACENativeMenuNeedsTextRetry(native),@"ready native text must clear the retry state");
    NativeTestAction *spacer = [NativeTestAction new]; spacer.button = [YTSpacerButton new];
    NSArray *elements = @[VirtualAction(@"Lock screen",0,handler),VirtualAction(@"Other settings",1,handler),
        VirtualAction(@"Indexed virtual label",2,handler),VirtualAction(@"Yoga-only text",3,handler),
        VirtualAction(@"Materialized controller text",4,handler)];
    native.actions = @[spacer,elements[0],spacer,elements[1],elements[2],spacer];
    actions = YTKACENativePlayerActions(native);
    Check(actions.count == 3,@"known empty spacers must not invalidate complete native actions");
    native.actions = elements;
    actions = YTKACENativePlayerActions(native);
    Check(actions.count == 5 && [actions[3][@"title"] isEqual:@"Yoga-only text"] &&
        [actions[4][@"title"] isEqual:@"Materialized controller text"],
        @"layer-backed yoga and controller-only text must survive absent subnodes/views/accessibility");
    NSArray *elementTitles = @[@"Lock screen",@"Other settings",@"Indexed virtual label",
        @"Yoga-only text",@"Materialized controller text"];
    for (NSUInteger index = 0; index < actions.count; ++index)
        Check([actions[index][@"title"] isEqual:elementTitles[index]],@"ELM node and non-view accessibility labels must decode");
    ((dispatch_block_t)actions[0][@"handler"])();
    Check(calls == 2,@"virtual element action must retain the original handler");
    NativeTestAction *heading = [NativeTestAction new];
    YTSpacerButton *named = [YTSpacerButton new]; [named setTitle:@"Native heading" forState:UIControlStateNormal];
    named.enabled = NO; heading.button = named; native.actions = @[heading];
    Check(YTKACENativePlayerActions(native).count == 1,@"spacers carrying text must not be discarded");
    NativeTestAction *unknown = [NativeTestAction new]; unknown.button = [UIButton new]; native.actions = @[unknown];
    Check(!YTKACENativePlayerActions(native),@"unknown empty rows must not be silently discarded");
    native.actions = @[spacer];
    Check(!YTKACENativePlayerActions(native),@"a spacer-only native sheet must not create an empty replacement");
    NativeTestAction *unresolved = [NativeTestAction new]; unresolved.handler = handler;
    YTMenuItemElementsMDCButton *cyclicButton = [YTMenuItemElementsMDCButton new]; unresolved.button = cyclicButton;
    NativeTestNodeView *cyclicView = [NativeTestNodeView new]; cyclicButton.elementView = cyclicView;
    NativeTestNode *cycle = [NativeTestNode new]; cycle.subnodes = @[cycle]; cyclicView.keepalive_node = cycle;
    native.actions = @[unresolved];
    Check(!YTKACENativePlayerActions(native) && YTKACENativeMenuNeedsTextRetry(native),@"cyclic node graphs must finish without inventing a label");
    cycle.subnodes = nil;
    NativeTestAction *rendererAction = [NativeTestAction new]; rendererAction.handler = handler;
    NativeTestRenderer *renderer = [NativeTestRenderer new]; renderer.menuItemIdentifier = @"menu_item_captions";
    NativeTestFormattedText *formattedText = [NativeTestFormattedText new]; formattedText.plain = @"Captions from renderer";
    renderer.text = formattedText;
    YTMenuController *builder = [YTMenuController new]; builder.actions = @[rendererAction];
    native.actions = [builder actionsForRenderers:@[renderer] fromView:self.button entry:nil shouldLogItems:NO firstResponder:nil];
    Check([YTKACENativePlayerActions(native).firstObject[@"title"] isEqual:@"Captions from renderer"],@"native navigation renderer text must survive absent view text");
}
- (void)testSettingsScope {
    UIButton *settings = [UIButton buttonWithType:UIButtonTypeSystem];
    settings.frame = CGRectMake(20, 160, 100, 44);
    YTKACERegisterTweakPlayerMenuSource(settings);
    [self.root.view addSubview:settings]; // Outside the player overlay.
    Check(YTKACEPresentSystemMenu(self.root, settings, @"Settings", nil, self.actions), @"settings did not present");
    Later(^{
        UIViewController *menu = self.root.presentedViewController;
        Check(!YTKACEIsPlayerPopover(menu), @"settings incorrectly became a player popover");
        UINavigationController *navigation = MenuNavigation(menu);
        UITableViewController *table = (id)navigation.topViewController;
        CGFloat slack = table.tableView.bounds.size.height - table.tableView.contentSize.height -
            table.tableView.contentInset.top - table.tableView.contentInset.bottom;
        Check(slack < 48, [NSString stringWithFormat:@"short settings sheet blank footer=%.1f window=%@ table=%@ content=%@ preferred=%@",slack,
            NSStringFromCGRect(self.window.bounds),NSStringFromCGRect(table.tableView.bounds),
            NSStringFromCGSize(table.tableView.contentSize),NSStringFromCGSize(menu.preferredContentSize)]);
        [menu dismissViewControllerAnimated:NO completion:^{
            [settings removeFromSuperview];
            [self testTimerList];
        }];
    });
}
- (void)testTimerList {
    NSMutableArray *actions = [NSMutableArray array];
    for (NSString *title in @[@"Off",@"10 minutes",@"15 minutes",@"20 minutes",@"30 minutes",@"45 minutes",@"1 hour",@"End of video"])
        [actions addObject:@{@"title":title}];
    Check(YTKACEPresentSystemMenu(self.root,self.button,@"Sleep Timer",nil,actions), @"timer menu did not present");
    Later(^{
        UIViewController *menu = self.root.presentedViewController;
        UITableViewController *table = (id)MenuNavigation(menu).topViewController;
        CGFloat slack = table.tableView.bounds.size.height - table.tableView.contentSize.height -
            table.tableView.contentInset.top - table.tableView.contentInset.bottom;
        Check(slack < 24, @"eight-row timer menu has excessive blank footer");
        [menu dismissViewControllerAnimated:NO completion:^{ [self testLongList]; }];
    });
}
- (void)testLongList {
    NSMutableArray *actions = [NSMutableArray array];
    for (NSUInteger index = 0; index < 30; ++index)
        [actions addObject:@{@"title": [NSString stringWithFormat:@"Option %lu", (unsigned long)index]}];
    Check(YTKACEPresentSystemMenu(self.root, self.button, @"Long menu", nil, actions), @"long menu did not present");
    Later(^{
        UIViewController *menu = self.root.presentedViewController;
        UITableViewController *content = (id)MenuNavigation(menu).topViewController;
        Check(content.tableView.contentSize.height > content.tableView.bounds.size.height, @"long list not scrollable");
        [menu dismissViewControllerAnimated:NO completion:^{
            [self.nativeButton addTarget:self action:@selector(openNative:) forControlEvents:UIControlEventTouchUpInside];
            YTKACERememberPlayerMenuSource(self.qualityButton);
            [self.nativeButton sendActionsForControlEvents:UIControlEventTouchUpInside];
            Later(^{ [self verifyNative]; });
        }];
    });
}
- (void)openNative:(UIButton *)sender {
    (void)sender;
    // Simulate the window's origin observation for a native UIAction/touch path
    // that bypasses sendAction:. A fresh tweak token must be discarded too.
    YTKACERememberPlayerMenuSource(self.qualityButton);
    YTKACEUpdatePlayerMenuTouchSource(self.nativeButton,self.window);
    UIViewController *native = self.nativeMenu;
    if (!native) {
        native = [YTBottomSheetController new];
        native.modalPresentationStyle = UIModalPresentationPageSheet;
        native.transitioningDelegate = self;
        native.preferredContentSize = CGSizeMake(320,280);
        YTDraggableView *panel = [[YTDraggableView alloc] initWithFrame:CGRectMake(0,0,320,280)];
        panel.backgroundColor = UIColor.systemBackgroundColor;
        [native.view addSubview:panel];
        NativeOriginAction *opaque = [NativeOriginAction new]; opaque.handler = ^{};
        ((YTBottomSheetController *)native).actions = @[opaque];
        self.nativeMenu = native;
    }
    self.nativeOpens++;
    [self.root presentViewController:native animated:NO completion:^{
        self.nativeCompletions++;
        Check(native.view.alpha == 1,@"native origin must not be hidden during original presentation completion");
    }];
}
- (void)verifyNative {
    UIViewController *native = self.root.presentedViewController;
    Check(native == self.nativeMenu && !YTKACEIsPlayerPopover(native) &&
        native.modalPresentationStyle == UIModalPresentationPageSheet && native.transitioningDelegate == self,
        @"native sheet presentation and transitioning delegate must be preserved across repeated opens");
    Check(CGSizeEqualToSize(native.preferredContentSize,CGSizeMake(320,280)), @"native content size must not be replaced by an estimated popover size");
    Check(!YTKACEIsPlayerMenuSource(self.nativeButton) && YTKACEIsPlayerMenuSource(self.qualityButton),
        @"source registration, not icon or accessibility identifier, must determine ownership");
    Check(NativeOriginReads == 0 && self.nativeCompletions == (NSUInteger)self.nativeOpens && !native.presentedViewController,
        @"native menus must never enter model decoding or create a replacement list");
    for (UIGestureRecognizer *gesture in native.presentationController.containerView.gestureRecognizers)
        Check(![NSStringFromClass([gesture.delegate class]) isEqual:@"YTKACENativeOutsideTap"],
            @"native origin must keep original dismissal gestures without our fallback recognizer");
    UIView *panel = native.view.subviews.firstObject;
    NSUInteger glassCount = 0;
    for (UIView *child in panel.subviews) if ([child isKindOfClass:UIVisualEffectView.class]) {
        ++glassCount;
        Check(!child.userInteractionEnabled && CGRectEqualToRect(child.frame,panel.bounds), @"native glass must only style the panel");
    }
    Check(glassCount == 1, @"native sheet must reuse one Liquid Glass surface");
    if (self.nativeOpens == 1) {
        YTBottomSheetController *submenu = [YTBottomSheetController new];
        submenu.actions = ((YTBottomSheetController *)native).actions;
        submenu.modalPresentationStyle = UIModalPresentationPageSheet;
        [native presentViewController:submenu animated:NO completion:nil];
        Later(^{
            Check(native.presentedViewController == submenu && !YTKACEIsPlayerPopover(submenu) &&
                submenu.view.alpha == 1 && NativeOriginReads == 0,@"native gear submenus must stay on the original path");
            [submenu dismissViewControllerAnimated:NO completion:^{ [self finishNativeOrigin]; }];
        });
        return;
    }
    [self finishNativeOrigin];
}
- (void)finishNativeOrigin {
    UIViewController *native = self.nativeMenu;
    [native dismissViewControllerAnimated:NO completion:^{
        if (self.nativeOpens < 3) {
            YTKACERememberPlayerMenuSource(self.qualityButton);
            [self.nativeButton sendActionsForControlEvents:UIControlEventTouchUpInside];
            Later(^{ [self verifyNative]; });
            return;
        }
        [self testAdaptedNative];
    }];
}
- (void)testAdaptedNative {
    if (!self.adaptedNative) {
        self.adaptedNative = [YTBottomSheetController new];
        self.adaptedNative.modalPresentationStyle = UIModalPresentationCustom;
        self.adaptedNative.transitioningDelegate = self;
        __weak PlayerMenuSmoke *weak = self;
        NativeTestAction *zero = [NativeTestAction new];
        zero.button = [UIButton buttonWithType:UIButtonTypeCustom];
        zero.handler = ^{ weak.adaptedCallbacks++; };
        self.adaptedNative.lateTitleButton = zero.button;
        NativeTestAction *one = [NativeTestAction new]; one.title = @"Native action argument";
        __weak NativeTestAction *weakOne = one;
        one.handler = ^(id selected) {
            Check(selected == weakOne,@"original native action argument must be preserved");
            weak.adaptedCallbacks++;
        };
        YTActionSheetAction *quality = [YTActionSheetAction actionWithTitle:@"Native element quality route"
            currentValue:@"Auto" iconImage:nil accessibilityIdentifier:nil handler:nil];
        self.nativeResponder = [NativeTestResponder new];
        self.nativeResponder.callback = ^{ weak.adaptedCallbacks++; };
        NSMutableArray *renderers = [NSMutableArray array];
        for (NSString *name in @[@"zero",@"one",@"menu_item_video_quality"]) {
            NativeTestRenderer *renderer = [NativeTestRenderer new]; renderer.menuItemIdentifier = name;
            [renderers addObject:renderer];
        }
        NativeTestAction *spacer = [NativeTestAction new]; spacer.button = [YTSpacerButton new];
        NativeTestAction *ax = [NativeTestAction new]; ax.handler = ^{ weak.adaptedCallbacks++; };
        self.opaqueParent = [[UIView alloc] initWithFrame:CGRectMake(20,80,320,56)];
        [self.adaptedNative.view addSubview:self.opaqueParent];
        self.opaqueButton = [NativeTestOpaqueButton new]; ax.button = self.opaqueButton;
        self.opaqueButton.opaque = NO; self.opaqueButton.backgroundColor = UIColor.clearColor;
        [self.opaqueParent addSubview:self.opaqueButton];
        self.opaqueButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.opaqueWidth = [self.opaqueButton.widthAnchor constraintEqualToConstant:320];
        [NSLayoutConstraint activateConstraints:@[self.opaqueWidth,
            [self.opaqueButton.heightAnchor constraintEqualToConstant:56],
            [self.opaqueButton.leadingAnchor constraintEqualToAnchor:self.opaqueParent.leadingAnchor],
            [self.opaqueButton.topAnchor constraintEqualToAnchor:self.opaqueParent.topAnchor]]];
        [self.opaqueButton addTarget:self.opaqueButton action:@selector(nativeTap) forControlEvents:UIControlEventTouchUpInside];
        NativeTestAction *node = VirtualAction(@"Other settings",4,^{ weak.adaptedCallbacks++; });
        NativeTestAction *indexed = VirtualAction(@"Captions",2,^{ weak.adaptedCallbacks++; });
        NativeTestAction *last = [NativeTestAction new]; last.title = @"Final native action";
        last.handler = ^{ weak.adaptedCallbacks++; };
        YTMenuController *builder = [YTMenuController new]; builder.actions = @[zero,one,quality,ax,node,indexed,last,spacer];
        NativeTestOwner *owner = [NativeTestOwner new]; owner.native = self.adaptedNative;
        owner.actions = [builder actionsForRenderers:renderers fromView:self.button
            entry:nil shouldLogItems:NO firstResponder:self.nativeResponder];
        self.adaptedNative.actionsController = owner;
    }
    UIButton *source = self.adaptedRound < 2 ? self.qualityButton : self.button;
    [self.adaptedNative.lateTitleButton setTitle:nil forState:UIControlStateNormal];
    YTKACERememberPlayerMenuSource(source);
    [self.root presentViewController:self.adaptedNative animated:YES completion:nil];
    Later(^{
        UIViewController *native = self.root.presentedViewController;
        UIViewController *menu = native.presentedViewController;
        Check(native == self.adaptedNative && native.transitioningDelegate == self &&
            native.modalPresentationStyle == UIModalPresentationCustom,@"adaptation must preserve the native sheet lifecycle");
        Check(menu && YTKACEIsPlayerPopover(menu) && menu.popoverPresentationController.sourceView == source,
            @"native action model must render beside the player button");
        for (UIView *view = menu.view; view; view = view.superview)
            Check(!view.hidden && view.alpha > 0,@"replacement menu must not inherit hidden native content");
        Check(native.view.alpha == 0,@"native bottom-sheet content must not show behind the replacement list");
        UITableViewController *rendered = (id)MenuNavigation(menu).topViewController;
        Check([rendered.tableView numberOfRowsInSection:0] == 7,@"quality-style trailing spacer must not create a row or reject the list");
        UITableViewCell *opaque = [rendered.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]];
        Check(self.opaqueButton.superview == opaque.contentView && !self.opaqueButton.userInteractionEnabled,
            @"an unreadable but rendered ELM row must be the same live control inside the popover, with table-owned selection");
        Check(!self.opaqueWidth.active && !opaque.textLabel.text.length && self.opaqueButton.bounds.size.width > 100,
            @"borrowed row must lay out at the table width without guessed text or active native-parent constraints");
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--preview-native-row"]) {
            [@"READY: live opaque row" writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/preview-ready.txt"]
                atomically:YES encoding:NSUTF8StringEncoding error:nil];
            return;
        }
        if (self.adaptedRound == 0) [menu dismissViewControllerAnimated:NO completion:nil];
        else {
            UITableViewController *table = (id)MenuNavigation(menu).topViewController;
            [table.tableView.delegate tableView:table.tableView didSelectRowAtIndexPath:
                [NSIndexPath indexPathForRow:self.adaptedRound - 1 inSection:0]];
        }
        Later(^{
            Check(!self.root.presentedViewController,@"closing replacement list must close the native session");
            Check(self.adaptedCallbacks == self.adaptedRound,@"native selection must run exactly once after dismissal");
            if (self.adaptedRound == 3)
                Check(self.nativeResponder.lastSource == self.button,@"element quality route must retain the original native responder and source");
            Check(self.adaptedNative.view.alpha == 1,@"native view alpha must restore on close");
            Check(self.opaqueButton.superview == self.opaqueParent && self.opaqueWidth.active &&
                !self.opaqueButton.translatesAutoresizingMaskIntoConstraints && self.opaqueButton.userInteractionEnabled &&
                self.opaqueButton.nativeTargetCalls == 0,@"native rows must restore hierarchy, constraints and interaction without duplicate native target delivery");
            self.adaptedRound++;
            if (self.adaptedRound < 6) [self testAdaptedNative];
            else [self testNativeOutsideDismissal];
        });
    });
}
- (void)testNativeOutsideDismissal {
    Check(NativePresentations == 6 && NativeDismissals == 6,@"original callbacks must run for every adapted menu");
    YTBottomSheetController *native = [YTBottomSheetController new];
    native.modalPresentationStyle = UIModalPresentationCustom; native.transitioningDelegate = self;
    NativeTestAction *unreadable = [NativeTestAction new];
    unreadable.button = [YTMenuItemElementsMDCButton new]; unreadable.handler = ^{};
    NativeTestOwner *owner = [NativeTestOwner new]; owner.native = native; owner.actions = @[unreadable];
    native.actionsController = owner;
    YTDraggableView *panel = [[YTDraggableView alloc] initWithFrame:CGRectMake(30,240,280,300)];
    [native.view addSubview:panel];
    YTKACERememberPlayerMenuSource(self.button);
    [self.root presentViewController:native animated:NO completion:nil];
    Later(^{
        Check(!native.presentedViewController && native.view.alpha == 1,@"unreadable rows must retain visible native controls");
        UIView *container = native.presentationController.containerView;
        UITapGestureRecognizer *outside = nil;
        for (UITapGestureRecognizer *gesture in container.gestureRecognizers)
            if ([NSStringFromClass([gesture.delegate class]) isEqual:@"YTKACENativeOutsideTap"]) outside = gesture;
        Check(outside != nil && !outside.cancelsTouchesInView,@"native fallback must install a non-cancelling outside recognizer");
        NativeTestTouch *touch = [NativeTestTouch new]; touch.referenceView = panel;
        touch.point = CGPointMake(50,50);
        Check(![outside.delegate gestureRecognizer:outside shouldReceiveTouch:touch],@"inside panel touches must reach native controls");
        panel.transform = CGAffineTransformMakeTranslation(0,40);
        touch.referenceView = container; touch.point = [panel convertPoint:CGPointMake(50,-20) toView:container];
        Check([outside.delegate gestureRecognizer:outside shouldReceiveTouch:touch],@"outside hit testing must use the current transformed panel frame");
        Features = NO;
        Check(![outside.delegate gestureRecognizer:outside shouldReceiveTouch:touch],@"disabled menus must not intercept outside taps");
        Features = YES;
        panel.hidden = YES;
        Check(![outside.delegate gestureRecognizer:outside shouldReceiveTouch:touch],@"unknown/hidden panels must keep native behavior");
        panel.hidden = NO;
        UIView *hiddenParent = [[UIView alloc] initWithFrame:native.view.bounds];
        [native.view addSubview:hiddenParent]; [hiddenParent addSubview:panel]; hiddenParent.hidden = YES;
        Check(![outside.delegate gestureRecognizer:outside shouldReceiveTouch:touch],@"panels under hidden parents must not accept outside cancellation");
        [native.view addSubview:panel]; [hiddenParent removeFromSuperview];
        // Drive the existing recognizer's normal target/action delivery after
        // verifying the exact touch acceptance path above.
        outside.state = UIGestureRecognizerStateEnded;
        Later(^{
            Check(!self.root.presentedViewController && owner.dismissals == 1,@"outside cancellation must close the native owner exactly once");
            Check(NativePresentations == 7 && NativeDismissals == 7,@"fallback close must retain native transition callbacks");
            [self testGearPopover];
        });
    });
}
- (YTBottomSheetController *)gearController:(dispatch_block_t)handler {
    YTBottomSheetController *native = [YTBottomSheetController new];
    native.modalPresentationStyle = UIModalPresentationCustom; native.transitioningDelegate = self;
    if (![NSProcessInfo.processInfo.arguments containsObject:@"--preview-native-gear"])
        native.hideSourceOnAppearance = self.gearButton;
    YTDraggableView *panel = [[YTDraggableView alloc] initWithFrame:CGRectMake(20,80,320,88)];
    [native.view addSubview:panel];
    NativeOriginAction *model = [NativeOriginAction new]; model.handler = handler;
    NativeTestOpaqueButton *button = [[NativeTestOpaqueButton alloc] initWithFrame:CGRectMake(0,0,320,56)];
    button.opaque = NO; button.backgroundColor = UIColor.clearColor;
    [panel addSubview:button]; model.button = button;
    NativeTestAction *spacer = [NativeTestAction new]; spacer.button = [[YTSpacerButton alloc] initWithFrame:CGRectMake(0,56,320,32)];
    [panel addSubview:spacer.button];
    NativeTestOwner *owner = [NativeTestOwner new]; owner.native = native; owner.actions = @[model,spacer];
    native.actionsController = owner;
    return native;
}
- (void)testGearPopover {
    if (!self.gearButton) {
        self.gearButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.gearButton.frame = CGRectMake(self.button.frame.origin.x,170,44,44);
        self.gearButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [self.gearButton setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
        [self.button.superview addSubview:self.gearButton];
        YTKACERegisterNativeGearMenuSource(self.gearButton);
        __weak PlayerMenuSmoke *weak = self;
        self.gearNative = [self gearController:^{
            weak.gearCallbacks++;
            weak.gearChild = [weak gearController:^{ weak.gearChildCallbacks++; }];
            [weak.root presentViewController:weak.gearChild animated:NO completion:nil];
        }];
    }
    self.gearButton.hidden = NO;
    self.gearButton.transform = CGAffineTransformIdentity;
    self.gearAnchorRect = [self.gearButton convertRect:self.gearButton.bounds toView:self.window];
    YTKACEUpdatePlayerMenuTouchSource(self.gearButton,self.window);
    [self.root presentViewController:self.gearNative animated:NO completion:nil];
    Later(^{
        UIViewController *menu = self.gearNative.presentedViewController;
        Check(menu && YTKACEIsPlayerPopover(menu) && menu.modalPresentationStyle == UIModalPresentationPopover,
            @"the actual native gear route must produce an anchored popover rather than retain a bottom sheet");
        BOOL preview = [NSProcessInfo.processInfo.arguments containsObject:@"--preview-native-gear"];
        Check((self.gearButton.hidden || preview) && menu.popoverPresentationController.sourceView == self.window &&
            CGRectEqualToRect(menu.popoverPresentationController.sourceRect,self.gearAnchorRect),
            @"a gear hidden/scaled by native appearance must retain its pre-presentation window-space anchor");
        Check(NativeOriginReads == 0,@"native gear content must use live rows without requiring title extraction");
        UITableViewController *table = (id)MenuNavigation(menu).topViewController;
        Check([table.tableView numberOfRowsInSection:0] == 1,@"native gear rows must be present in the actual popover");
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--preview-native-gear"]) {
            [@"READY: hidden native gear anchored to window rect" writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/gear-preview.txt"]
                atomically:YES encoding:NSUTF8StringEncoding error:nil]; return;
        }
        if (!self.gearRound) [menu dismissViewControllerAnimated:NO completion:nil];
        else [table.tableView.delegate tableView:table.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        Later(^{
            if (!self.gearRound) {
                Check(!self.root.presentedViewController,@"native gear cancellation must release its original owner");
                self.gearRound++; [self testGearPopover]; return;
            }
            UIViewController *childMenu = self.gearChild.presentedViewController;
            Check(childMenu && YTKACEIsPlayerPopover(childMenu) && childMenu.popoverPresentationController.sourceView == self.window,
                @"a gear quality submenu must retain the same window-space gear anchor after its parent closes");
            UITableViewController *childTable = (id)MenuNavigation(childMenu).topViewController;
            [childTable.tableView.delegate tableView:childTable.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
            Later(^{
                Check(!self.root.presentedViewController && self.gearCallbacks == 1 && self.gearChildCallbacks == 1,
                    @"gear and submenu actions must run once and close both native owners");
                Check([(NativeTestOwner *)self.gearNative.actionsController dismissals] == 2 &&
                    [(NativeTestOwner *)self.gearChild.actionsController dismissals] == 1,@"native gear owner state must release on every open");
                Check(NativePresentations == 10 && NativeDismissals == 10,@"gear anchoring must preserve native presentation lifecycle");
                [self testUnrelated];
            });
        });
    });
}
- (void)testUnrelated {
        Check(NativePresentations == 10 && NativeDismissals == 10,@"original custom presentation/dismissal callbacks must run for every menu");
        Check([(NativeTestOwner *)self.adaptedNative.actionsController dismissals] == 6,
            @"original action owner's dismissal API must run on cancellation and selection");
        UIViewController *unrelated = [UIViewController new];
        unrelated.modalPresentationStyle = UIModalPresentationPageSheet;
        [self.root presentViewController:unrelated animated:NO completion:nil];
        Later(^{
            Check(!YTKACEIsPlayerPopover(unrelated), @"unrelated controller was changed");
            [unrelated dismissViewControllerAnimated:NO completion:^{
                Features = NO;
                Check(!YTKACEPresentSystemMenu(self.root, self.button, @"Off", nil, self.actions), @"disabled preference ignored");
                Features = YES;
                YTKACEPresentSystemMenu(self.root, self.button, @"Player options", nil, self.actions);
                Later(^{ [self testRotation]; });
            }];
        });
}
- (UIPresentationController *)presentationControllerForPresentedViewController:(UIViewController *)presented
    presentingViewController:(UIViewController *)presenting sourceViewController:(UIViewController *)source {
    (void)source;
    if (presented.modalPresentationStyle != UIModalPresentationCustom) return nil;
    return [[NativeTestPresentation alloc] initWithPresentedViewController:presented presentingViewController:presenting];
}
- (void)testRotation {
    UIWindowSceneGeometryPreferencesIOS *geometry = [[UIWindowSceneGeometryPreferencesIOS alloc]
        initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscapeRight];
    [self.window.windowScene requestGeometryUpdateWithPreferences:geometry errorHandler:^(NSError *error) {
        Check(NO, [@"rotation failed: " stringByAppendingString:error.localizedDescription]);
    }];
    Later(^{ Later(^{
        UIViewController *menu = self.root.presentedViewController;
        Check(self.window.bounds.size.width > self.window.bounds.size.height, @"landscape rotation missing");
        Check(menu && YTKACEIsPlayerPopover(menu), @"popover lost during rotation");
        CGRect frame = [menu.view convertRect:menu.view.bounds toView:self.window];
        Check(CGRectContainsRect(CGRectInset(self.window.bounds, -1, -1), frame), @"rotated popover exceeded window");
        [menu dismissViewControllerAnimated:NO completion:^{ [self testLandscapeSettings]; }];
    }); });
}
- (void)testLandscapeSettings {
    UIButton *settings = [[UIButton alloc] initWithFrame:CGRectMake(20,80,100,44)];
    [self.root.view addSubview:settings];
    Check(YTKACEPresentSystemMenu(self.root,settings,@"Landscape settings",nil,self.actions),@"landscape settings did not present");
    Later(^{
        UIViewController *menu = self.root.presentedViewController;
        UITableViewController *table = (id)MenuNavigation(menu).topViewController;
        CGFloat slack = table.tableView.bounds.size.height - table.tableView.contentSize.height -
            table.tableView.contentInset.top - table.tableView.contentInset.bottom;
        Check(slack < 48,@"compact-height settings must fit content instead of expanding to fullscreen");
        [menu dismissViewControllerAnimated:NO completion:^{
            [settings removeFromSuperview];
            YTKACEPresentSystemMenu(self.root,self.button,@"Player options",nil,self.actions);
            [@"PASS: native gear and submenu popovers, hidden-gear window anchors, live native rows without title reads, repeat cancel/select/owner lifecycle, tweak routing, bounds, scrolling, settings and rotation\n"
                writeToFile:ResultPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }];
    });
}
@end

int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(PlayerMenuSmoke.class)); }
}
