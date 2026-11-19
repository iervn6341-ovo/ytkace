#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import <objc/runtime.h>
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
static UIView *TransitionCover(UIWindow *window) {
    for (UIView *view in window.subviews)
        if ([view.accessibilityIdentifier isEqual:@"YTKACE.SubmenuTransition"]) return view;
    return nil;
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
@property(nonatomic) BOOL shouldDismissOnAction;
@end
@implementation NativeTestAction
- (instancetype)init { if ((self = [super init])) _shouldDismissOnAction = YES; return self; }
@end
static NSUInteger NativeOriginReads;
static NSUInteger GearExtensionCalls;
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
@implementation YTMenuItemElementsMDCButton
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) { self.opaque = NO; self.backgroundColor = UIColor.clearColor; } return self;
}
- (void)drawRect:(CGRect)rect {
    (void)rect;
    [@"Rendered native option" drawAtPoint:CGPointMake(16,16)
        withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:17],NSForegroundColorAttributeName:UIColor.labelColor}];
}
@end
@interface ELMTouchCommandPropertiesHandler : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic) NSUInteger calls;
@property(nonatomic, copy) dispatch_block_t callback;
- (void)handleTap;
@end
@implementation ELMTouchCommandPropertiesHandler
- (void)handleTap { self.calls++; if (self.callback) self.callback(); }
@end
@interface GOODialogView : UIView
@property(nonatomic, weak) UIViewController *native;
@property(nonatomic) NSUInteger closeCalls;
- (void)actionButtonDidTap:(id)sender;
@end
@implementation GOODialogView
- (void)actionButtonDidTap:(id)sender {
    (void)sender; self.closeCalls++;
    [self.native dismissViewControllerAnimated:NO completion:nil];
}
@end
static void InstallELMTap(UIView *view, ELMTouchCommandPropertiesHandler *handler, BOOL enabled) {
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:handler action:@selector(handleTap)];
    tap.delegate = handler; tap.enabled = enabled; [view addGestureRecognizer:tap];
    objc_setAssociatedObject(view,@selector(handleTap),handler,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
// Render pixels without exposing text/attributedText/accessibility data, just
// like the device's opaque ELM row. Its original control must remain intact.
@interface NativeTestOpaqueButton : YTMenuItemElementsMDCButton
@property(nonatomic) NSUInteger nativeTargetCalls;
@property(nonatomic) BOOL suppressRendering;
- (void)nativeTap;
@end
@implementation NativeTestOpaqueButton
- (void)drawRect:(CGRect)rect {
    (void)rect;
    if (self.suppressRendering) return;
    [@"Native element row" drawAtPoint:CGPointMake(16,16)
        withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:17],NSForegroundColorAttributeName:UIColor.labelColor}];
}
- (void)nativeTap { self.nativeTargetCalls++; }
@end
@interface NativeTestReparentedButton : NativeTestOpaqueButton
@property(nonatomic, weak) UIView *originalParent;
@end
@implementation NativeTestReparentedButton
- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    if (self.originalParent && self.superview != self.originalParent) {
        self.suppressRendering = YES; self.layer.contents = nil; [self setNeedsDisplay];
    }
}
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
// Two passive targets reproduce the device's targets=2 without a navigation action.
@interface NativePassiveTarget : NSObject
@property(nonatomic) NSUInteger calls;
- (void)inkTap:(id)sender;
@end
@implementation NativePassiveTarget
- (void)inkTap:(id)sender { (void)sender; self.calls++; }
@end
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
@property(nonatomic, strong) UIView *lateGeometryButton;
@end
@implementation YTBottomSheetController
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.hideSourceOnAppearance.hidden = YES;
    self.hideSourceOnAppearance.transform = CGAffineTransformMakeScale(0.01,0.01);
    [self.lateTitleButton setTitle:@"Native appearance-time title" forState:UIControlStateNormal];
    if (self.lateGeometryButton) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,80 * NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        CGRect frame = self.lateGeometryButton.frame; frame.size.height = 56;
        self.lateGeometryButton.frame = frame;
        [self.lateGeometryButton setNeedsDisplay];
        [self.view setNeedsLayout];
    });
}
@end
@interface NativeSettingsPage : UIViewController
@property(nonatomic, copy) NSArray *actions;
@property(nonatomic, strong) UIView *lateGeometryButton;
@end
@implementation NativeSettingsPage
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,80 * NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        CGRect frame = self.lateGeometryButton.frame; frame.size.height = 56;
        self.lateGeometryButton.frame = frame;
        [self.lateGeometryButton setNeedsDisplay]; [self.view setNeedsLayout];
    });
}
@end

@interface NativeSelectorSheet : YTBottomSheetController
@property(nonatomic) NSUInteger closeRequests;
@end
@implementation NativeSelectorSheet
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion {
    self.closeRequests++;
    [super dismissViewControllerAnimated:animated completion:completion];
}
@end

@interface NativeTestOwner : NSObject
@property(nonatomic, copy) NSArray *actions;
@property(nonatomic, weak) UIViewController *native;
@property(nonatomic) NSUInteger dismissals;
@property(nonatomic) NSTimeInterval dismissalDelay;
@property(nonatomic) BOOL clearsActionsOnDismiss;
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion;
@end
@implementation NativeTestOwner
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion {
    self.dismissals++;
    if (self.clearsActionsOnDismiss) { self.actions = nil; [(id)self.native setActionsController:nil]; }
    if (self.dismissalDelay > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(self.dismissalDelay * NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            [self.native dismissViewControllerAnimated:animated completion:completion];
        });
    } else [self.native dismissViewControllerAnimated:animated completion:completion];
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
        } else if ([NSProcessInfo.processInfo.arguments containsObject:@"--composite-quality-regression"]) {
            [self testCompositeQuality];
        } else if ([NSProcessInfo.processInfo.arguments containsObject:@"--rebuild-back-regression"]) {
            [self testRebuiltBack];
        } else if ([NSProcessInfo.processInfo.arguments containsObject:@"--elm-command-regression"]) {
            [self testELMCommandOrder:[NSProcessInfo.processInfo.arguments containsObject:@"--late-back-regression"] ? 11 :
                ([NSProcessInfo.processInfo.arguments containsObject:@"--retained-back-regression"] ? 3 : 0)];
        } else if ([NSProcessInfo.processInfo.arguments containsObject:@"--native-activation-regression"]) {
            [self testNativeActivation:0];
        } else if ([NSProcessInfo.processInfo.arguments containsObject:@"--menu-lifecycle-regression"] ||
            [NSProcessInfo.processInfo.arguments containsObject:@"--real-menu-lifecycle"]) {
            [self testMenuLifecycle:0];
        } else if ([NSProcessInfo.processInfo.arguments containsObject:@"--row-rendering-regression"]) {
            [self testRowRendering:0];
        } else [self testOwnedMenu];
    });
}
- (void)testRowRendering:(NSUInteger)mode {
    UIButton *gear = [UIButton buttonWithType:UIButtonTypeSystem]; gear.frame = CGRectMake(240,140,44,44);
    [self.button.superview addSubview:gear]; YTKACERegisterNativeGearMenuSource(gear);
    YTBottomSheetController *native = [YTBottomSheetController new];
    native.modalPresentationStyle = UIModalPresentationCustom; native.transitioningDelegate = self;
    YTDraggableView *panel = [[YTDraggableView alloc] initWithFrame:CGRectMake(8,80,320,120)];
    [native.view addSubview:panel];
    NativeTestReparentedButton *button = [[NativeTestReparentedButton alloc] initWithFrame:CGRectMake(0,0,320,56)];
    button.opaque = NO; button.backgroundColor = UIColor.clearColor; [panel addSubview:button];
    button.originalParent = panel; button.suppressRendering = mode == 1;
    ELMTouchCommandPropertiesHandler *command = [ELMTouchCommandPropertiesHandler new]; InstallELMTap(button,command,YES);
    NativeTestAction *action = [NativeTestAction new]; action.button = button;
    action.handler = ^{ Check(NO,@"rendering fallback must not execute a placeholder callback"); };
    NativeTestOwner *owner = [NativeTestOwner new]; owner.native = native; owner.actions = @[action]; native.actionsController = owner;
    YTKACERememberPlayerMenuSource(gear); [self.root presentViewController:native animated:NO completion:nil];
    Later(^{
        UIViewController *menu = native.presentedViewController;
        if (mode == 1) {
            Check(!menu && native.view.alpha == 1 && command.calls == 0 && owner.dismissals == 0 && button.superview == panel,
                @"never-rendered native rows must restore the original sheet, not leave a clickable blank popover");
            [native dismissViewControllerAnimated:NO completion:^{
                [gear removeFromSuperview];
                [self testRowRendering:2];
            }]; return;
        }
        Check(YTKACEIsPlayerPopover(menu) && button.superview == panel,@"a node cleared on reparent must use its original pixels without remaining borrowed");
        UITableViewController *table = (id)MenuNavigation(menu).topViewController;
        if (mode == 2) {
            NSDictionary *item = [[table valueForKey:@"actions"] firstObject];
            [item[@"nativeRow"] setValue:nil forKey:@"rendering"];
            [table viewDidAppear:NO]; // Queue the delayed blank check, then cancel first.
            [menu dismissViewControllerAnimated:YES completion:nil];
            Later(^{
                Check(!self.root.presentedViewController && owner.dismissals == 1 && command.calls == 0,
                    @"a pending blank check must not restore the native sheet after cancellation starts");
                [gear removeFromSuperview];
                [@"PASS: pre-reparent pixels survive invalidation; missing pixels restore native UI; pending blank checks respect cancellation\n"
                    writeToFile:ResultPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }); return;
        }
        UITableViewCell *cell = [table.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        BOOL image = NO;
        for (UIView *view in cell.contentView.subviews) if ([view isKindOfClass:UIImageView.class] && [(UIImageView *)view image].CGImage) image = YES;
        Check(image,@"reparent recovery must visibly contain an owned native-row image");
        [table.tableView.delegate tableView:table.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        Later(^{
            Check(command.calls == 1 && owner.dismissals == 1 && !self.root.presentedViewController,@"reparent recovery must retain one original command and one dismissal");
            [gear removeFromSuperview]; [self testRowRendering:1];
        });
    });
}
- (void)testMenuLifecycle:(NSUInteger)mode {
    UIButton *gear = [UIButton buttonWithType:UIButtonTypeSystem];
    gear.frame = CGRectMake(240,140,44,44); [self.button.superview addSubview:gear];
    YTKACERegisterNativeGearMenuSource(gear);
    YTBottomSheetController *native = [YTBottomSheetController new];
    native.modalPresentationStyle = UIModalPresentationCustom; native.transitioningDelegate = self;
    YTDraggableView *panel = [[YTDraggableView alloc] initWithFrame:CGRectMake(8,80,320,160)];
    [native.view addSubview:panel];
    NativeTestOpaqueButton *button = [[NativeTestOpaqueButton alloc] initWithFrame:CGRectMake(0,0,320,56)];
    button.backgroundColor = UIColor.clearColor; button.opaque = NO; [panel addSubview:button];
    ELMTouchCommandPropertiesHandler *command = [ELMTouchCommandPropertiesHandler new];
    InstallELMTap(button,command,YES);
    NativeTestAction *action = [NativeTestAction new]; action.button = button;
    action.handler = ^{ Check(NO,@"resumed ELM row must not use the placeholder handler"); };
    NativeTestAction *extension = [NativeTestAction new]; extension.title = @"字幕動態島";
    extension.handler = ^{ Check(NO,@"lifecycle changes must not activate the metadata row"); };
    NativeTestOwner *owner = [NativeTestOwner new]; owner.native = native; owner.actions = @[action,extension];
    native.actionsController = owner;
    command.callback = ^{ Check(button.superview == panel && button.userInteractionEnabled,
        @"resumed command must use its original restored native hierarchy"); };
    YTKACERememberPlayerMenuSource(gear);
    [self.root presentViewController:native animated:NO completion:nil];
    Later(^{
        UIViewController *menu = native.presentedViewController;
        Check(YTKACEIsPlayerPopover(menu),@"lifecycle regression must start with an adapted native gear");
        UITableViewController *table = (id)MenuNavigation(menu).topViewController;
        UITableViewCell *cell = [table.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        Check(button.superview == cell.contentView,@"native row must be borrowed before suspension");
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--real-menu-lifecycle"]) {
            __block id inactiveToken, activeToken;
            __block BOOL inactive = NO;
            inactiveToken = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification) {
                    inactive = YES;
                    Check(button.superview == panel,@"actual app deactivation must return the native node before cache purge");
                    button.suppressRendering = YES; [button setNeedsDisplay]; [button.layer displayIfNeeded];
                    button.layer.contents = nil;
                    [@"INACTIVE: original ELM rendering purged after native hierarchy restoration\n"
                        writeToFile:ResultPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
                }];
            activeToken = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification) {
                    if (!inactive) return;
                    [NSNotificationCenter.defaultCenter removeObserver:inactiveToken];
                    [NSNotificationCenter.defaultCenter removeObserver:activeToken];
                    inactiveToken = nil; activeToken = nil;
                    Later(^{
                        UITableViewCell *resumed = [table.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
                        UIImageView *display = nil;
                        for (UIView *view in resumed.contentView.subviews) if ([view isKindOfClass:UIImageView.class]) display = (id)view;
                        Check(native.presentedViewController == menu && display.image.CGImage && button.superview == panel &&
                            command.calls == 0 && owner.dismissals == 0,@"actual app reactivation must show preserved native content without callbacks");
                        [table.tableView.delegate tableView:table.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
                        Later(^{
                            Check(!self.root.presentedViewController && command.calls == 1 && owner.dismissals == 1,
                                @"actual reactivation must retain exact-once ELM selection and owner cleanup");
                            [gear removeFromSuperview];
                            [@"PASS: actual app background/foreground with ELM render purge preserves menu pixels and exact-once selection\n"
                                writeToFile:ResultPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
                        });
                    });
                }];
            [@"READY: menu visible for real background/foreground regression\n"
                writeToFile:ResultPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
            return;
        }
        [NSNotificationCenter.defaultCenter postNotificationName:UISceneWillDeactivateNotification object:[NSObject new]];
        Check(button.superview == cell.contentView,@"another scene must not suspend this menu");
        if (mode == 3) {
            NSDictionary *item = [[table valueForKey:@"actions"] firstObject];
            [item[@"nativeRow"] setValue:nil forKey:@"rendering"]; // Inject an unavailable render cache.
        }
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:UIApplication.sharedApplication];
        [NSNotificationCenter.defaultCenter postNotificationName:UISceneWillDeactivateNotification object:self.window.windowScene];
        Check(button.superview == panel && button.userInteractionEnabled && native.view.alpha == 0,
            @"suspension must restore the live node without revealing the hidden native sheet");
        UIImageView *cached = nil;
        for (UIView *view in cell.contentView.subviews) if ([view isKindOfClass:UIImageView.class]) cached = (id)view;
        UIImage *image = cached.image;
        if (mode != 3) {
            Check(image.CGImage != nil,@"native glyph pixels must survive in an owned bitmap");
            CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(image.CGImage));
            BOOL ink = NO; const UInt8 *bytes = CFDataGetBytePtr(data);
            for (CFIndex i = 0; i < CFDataGetLength(data); i++) if (bytes[i]) { ink = YES; break; }
            CFRelease(data); Check(ink,@"preserved rendering must contain actual native glyph pixels");
        }
        // Reproduce an ELM cache purge while the original live node is at its owner.
        button.suppressRendering = YES; [button setNeedsDisplay]; [button.layer displayIfNeeded];
        button.layer.contents = nil;
        if (mode == 1) [menu dismissViewControllerAnimated:NO completion:nil];
        if (mode == 2) owner.actions = @[extension];
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:UIApplication.sharedApplication];
        [NSNotificationCenter.defaultCenter postNotificationName:UISceneDidActivateNotification object:self.window.windowScene];
        Later(^{
            if (mode == 0) {
                Check(native.presentedViewController == menu && command.calls == 0 && owner.dismissals == 0,
                    @"resuming must keep the same menu and must not execute any action");
                UITableViewCell *resumed = [table.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
                UIImageView *display = nil;
                for (UIView *view in resumed.contentView.subviews) if ([view isKindOfClass:UIImageView.class]) display = (id)view;
                Check(display.image == image && button.superview == panel,
                    @"foreground rendering must retain its pixels without remounting the purged ELM view");
                UITableViewCell *metadata = [table.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
                Check([metadata.textLabel.text isEqual:@"字幕動態島"],@"metadata rows must keep their normal text");
                [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:UIApplication.sharedApplication];
                [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:UIApplication.sharedApplication];
                [table.tableView.delegate tableView:table.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
            }
            Later(^{
                Check(!self.root.presentedViewController && owner.dismissals == 1 && command.calls == (mode == 0 ? 1u : 0u),
                    @"resume/select/cancel/stale-model/cache-miss paths must close once without extra callbacks");
                Check(!TransitionCover(self.window),@"lifecycle recovery must not leave a transition cover behind");
                [gear removeFromSuperview];
                if (mode < 3) [self testMenuLifecycle:mode + 1];
                else [@"PASS: repeated inactive/active cycles preserve opaque native glyphs, original ELM selection, metadata rows, scene isolation, cancellation and stale/cache-miss cleanup\n"
                    writeToFile:ResultPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
            });
        });
    });
}
- (void)testCompositeQuality {
    NSArray *flags = NSProcessInfo.processInfo.arguments;
    BOOL speed = [flags containsObject:@"--native-content-speed"];
    BOOL navigate = [flags containsObject:@"--content-next-step"];
    BOOL textInput = [flags containsObject:@"--content-text-input"];
    BOOL switchForm = [flags containsObject:@"--content-switch-form"];
    BOOL background = [flags containsObject:@"--content-background"];
    BOOL cancel = [flags containsObject:@"--content-cancel"] || background;
    if ([flags containsObject:@"--content-tweak-source"]) YTKACERegisterTweakPlayerMenuSource(self.nativeButton);
    else YTKACERegisterNativeGearMenuSource(self.nativeButton);
    NativeSelectorSheet *native = [NativeSelectorSheet new];
    native.title = speed ? @"Playback speed" : @"Video quality";
    native.modalPresentationStyle = UIModalPresentationCustom; native.transitioningDelegate = self;
    YTDraggableView *panel = [[YTDraggableView alloc] initWithFrame:CGRectMake(8,120,340,192)];
    panel.backgroundColor = UIColor.clearColor; [native.view addSubview:panel];
    UIPanGestureRecognizer *sheetPan = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:NULL];
    [panel addGestureRecognizer:sheetPan];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16,12,300,30)];
    label.text = speed ? @"Playback speed · 1.25×" : @"Quality for this video";
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth; [panel addSubview:label];
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(16,55,300,44)];
    slider.minimumValue = .25; slider.maximumValue = 5; slider.value = 1.25;
    slider.accessibilityLabel = @"Playback speed"; slider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [panel addSubview:slider];
    UIPanGestureRecognizer *sliderPan = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:NULL];
    [slider addGestureRecognizer:sliderPan];
    NativeTestAction *host = [NativeTestAction new];
    host.button = switchForm ? [UIControl new] : [YTSpacerButton new];
    [(UIView *)host.button setFrame:CGRectMake(0,0,340,switchForm ? 56 : 1)]; [panel addSubview:host.button];
    UISwitch *toggle = [UISwitch new]; toggle.frame = CGRectMake(240,10,52,32); toggle.on = YES;
    if (switchForm) [host.button addSubview:toggle];
    NativeTestAction *automatic = [NativeTestAction new]; automatic.title = @"Auto (recommended)";
    UIButton *choice = [UIButton buttonWithType:UIButtonTypeSystem];
    [choice setTitle:navigate ? @"Advanced" : (speed ? @"Normal · 1×" : @"Auto (recommended)") forState:UIControlStateNormal];
    choice.frame = CGRectMake(16,116,300,52); choice.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [panel addSubview:choice]; automatic.button = choice;
    NativeTestOwner *owner = [NativeTestOwner new]; owner.native = native;
    owner.clearsActionsOnDismiss = YES;
    owner.actions = [flags containsObject:@"--content-no-model"] ? nil : @[host,automatic];
    native.actionsController = owner;
    __block NSUInteger values = 0, choices = 0, leaves = 0;
    if (switchForm) {
        NativeTestAction *extra = [NativeTestAction new]; extra.title = @"Caption settings";
        extra.handler = ^{ choices++; };
        owner.actions = @[host,automatic,extra];
        [toggle addAction:[UIAction actionWithHandler:^(__unused UIAction *action) { values++; }]
            forControlEvents:UIControlEventValueChanged];
    }
    [slider addAction:[UIAction actionWithHandler:^(__unused UIAction *action) { values++; }]
        forControlEvents:UIControlEventValueChanged];
    [choice addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
        Check(native.presentingViewController && native.view.alpha == 1 && choices == 0,
            @"native selector actions must run against their live presented owner exactly once");
        choices++;
        if (textInput) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Custom speed" message:nil preferredStyle:UIAlertControllerStyleAlert];
            [alert addTextFieldWithConfigurationHandler:nil];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [self.root presentViewController:alert animated:NO completion:nil]; return;
        }
        if (!navigate) { [owner dismissViewControllerAnimated:NO completion:nil]; return; }
        YTBottomSheetController *child = [YTBottomSheetController new]; child.title = @"Advanced quality";
        YTDraggableView *childPanel = [[YTDraggableView alloc] initWithFrame:CGRectMake(0,100,340,100)];
        [child.view addSubview:childPanel];
        NativeTestAction *leaf = [NativeTestAction new];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectMake(0,0,340,56); [button setTitle:@"1080p" forState:UIControlStateNormal];
        [childPanel addSubview:button]; leaf.button = button; leaf.title = @"1080p"; leaf.handler = ^{ leaves++; };
        child.actions = @[leaf];
        [self.root presentViewController:child animated:NO completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    automatic.handler = ^{ Check(NO,@"the container must preserve original native controls, never dispatch a second model handler"); };
    CGRect originalFrame = panel.frame;
    YTKACERememberPlayerMenuSource(self.nativeButton);
    [self.root presentViewController:native animated:NO completion:nil];
    Later(^{
        UIViewController *menu = native.presentedViewController;
        UITableViewController *list = (id)MenuNavigation(menu).topViewController;
        Check(YTKACEIsPlayerPopover(menu) && [list.tableView numberOfRowsInSection:0] == (switchForm ? 2 : 1),
            @"composite selectors must use the same floating container as the gear menu");
        Check(panel.window && [panel isDescendantOfView:menu.view] && slider.userInteractionEnabled && panel.userInteractionEnabled,
            @"the complete native selector, including its slider and choices, must remain interactive");
        Check(!sheetPan.enabled && sliderPan.enabled,@"only the old sheet drag gesture must be suppressed inside the shared container");
        Check(native.view.alpha == 1 && native.view.layer.mask != nil && owner.dismissals == 0,
            @"the native owner must stay alive and visually masked behind its shared content page");
        slider.value = 1.75; [slider sendActionsForControlEvents:UIControlEventValueChanged];
        Check(values == 1 && fabs(slider.value - 1.75) < .001,@"continuous selection must reach the original native handler once");
        if (switchForm) {
            Check(toggle.userInteractionEnabled && [toggle isDescendantOfView:menu.view],@"native switches must remain live inside mixed forms");
            toggle.on = NO; [toggle sendActionsForControlEvents:UIControlEventValueChanged];
            Check(values == 2 && !toggle.on,@"mixed form toggles must keep their original value-change route");
        }
        if ([flags containsObject:@"--preview-native-content"]) {
            [@"READY: shared native content" writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/native-content-preview.txt"]
                atomically:YES encoding:NSUTF8StringEncoding error:nil]; return;
        }
        if (background) {
            [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
        } else if (cancel) {
            UIBarButtonItem *close = list.navigationItem.rightBarButtonItem;
            [UIApplication.sharedApplication sendAction:close.action to:close.target from:close forEvent:nil];
        } else if (switchForm) {
            [list.tableView.delegate tableView:list.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
        } else [choice sendActionsForControlEvents:UIControlEventTouchUpInside];
        Later(^{
            dispatch_block_t verify = ^{
                Check(!self.root.presentedViewController && native.closeRequests == 1 && owner.dismissals == 1 && choices == (cancel ? 0u : 1u) && leaves == (navigate ? 1u : 0u),
                    [NSString stringWithFormat:@"selector close must run once: root=%@ native=%lu owner=%lu choices=%lu leaves=%lu",
                        NSStringFromClass(self.root.presentedViewController.class),(unsigned long)native.closeRequests,
                        (unsigned long)owner.dismissals,(unsigned long)choices,(unsigned long)leaves]);
                Check(panel.superview == native.view && CGRectEqualToRect(panel.frame,originalFrame) && !native.view.layer.mask && sheetPan.enabled && sliderPan.enabled,
                    @"closing must restore the original selector hierarchy, geometry and mask");
                [@"PASS: shared native selector container, continuous controls, exact-once choices/cancel and container reuse\n"
                    writeToFile:ResultPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
            };
            if (textInput) {
                UIAlertController *alert = (id)self.root.presentedViewController;
                Check([alert isKindOfClass:UIAlertController.class] && alert.textFields.count == 1 && !YTKACEIsPlayerPopover(alert) && !TransitionCover(self.window),
                    @"native text entry must retain its fields and must not be converted to an action-only menu");
                [alert dismissViewControllerAnimated:NO completion:verify]; return;
            } else if (navigate) {
                UIViewController *child = self.root.presentedViewController;
                Check(YTKACEIsPlayerPopover(child.presentedViewController) && child.presentedViewController == menu,
                    @"a native selector child must reuse the existing floating container instance");
                UITableViewController *childList = (id)MenuNavigation(menu).topViewController;
                [childList.tableView.delegate tableView:childList.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
            }
            Later(verify);

        });
    });
}
// Real YTDefaultSheetController tears down its actions on dismissal. Every
// gear activation creates new controllers, owners and node graphs here.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
- (void)testRebuiltBack {
    UIButton *gear = [UIButton buttonWithType:UIButtonTypeSystem];
    gear.frame = CGRectMake(240,140,44,44); [self.button.superview addSubview:gear];
    YTKACERegisterNativeGearMenuSource(gear);
    __block NSUInteger generations = 0, leafCalls = 0;
    BOOL changedActions = [NSProcessInfo.processInfo.arguments containsObject:@"--changed-back-regression"];
    NSMutableArray<NativeTestOwner *> *owners = [NSMutableArray array];
    NSMutableArray<UIViewController *> *pages = [NSMutableArray array];
    __block YTBottomSheetController *(^makePage)(NSUInteger);
    makePage = ^YTBottomSheetController *(NSUInteger depth) {
        YTBottomSheetController *page = [YTBottomSheetController new];
        page.title = [NSString stringWithFormat:@"Page %lu",(unsigned long)depth];
        page.modalPresentationStyle = UIModalPresentationCustom; page.transitioningDelegate = self;
        YTDraggableView *panel = [[YTDraggableView alloc] initWithFrame:CGRectMake(8,80,320,180)];
        [page.view addSubview:panel];
        NativeTestOwner *owner = [NativeTestOwner new];
        owner.native = page; owner.clearsActionsOnDismiss = YES;
        [owners addObject:owner]; [pages addObject:page];
        NSMutableArray *actions = [NSMutableArray array];
        NSUInteger count = depth == 1 || (changedActions && depth == 0 && generations > 1) ? 2 : 1;
        for (NSUInteger row = 0; row < count; row++) {
            NativeTestAction *item = [NativeTestAction new];
            item.button = [[YTMenuItemElementsMDCButton alloc] initWithFrame:CGRectMake(0,row * 56,320,56)];
            [panel addSubview:item.button];
            if (depth < 2 && row == 0) {
                UIView *element = [[UIView alloc] initWithFrame:[item.button bounds]]; [item.button addSubview:element];
                ELMTouchCommandPropertiesHandler *command = [ELMTouchCommandPropertiesHandler new];
                InstallELMTap(element,command,YES);
                command.callback = ^{
                    Check(page.presentingViewController && owner.actions.count > 0,
                        @"rebuilt navigation must execute against a live owner and node graph");
                    YTBottomSheetController *child = makePage(depth + 1);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30 * NSEC_PER_MSEC),dispatch_get_main_queue(),^{
                        [self.root presentViewController:child animated:NO completion:nil];
                    });
                };
                item.handler = ^{ Check(NO,@"the placeholder action must not replace the ELM command"); };
            } else item.handler = ^{ leafCalls++; };
            [actions addObject:item];
        }
        owner.actions = actions; page.actionsController = owner;
        return page;
    };
    [gear addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
        generations++;
        YTKACERememberPlayerMenuSource(gear);
        [self.root presentViewController:makePage(0) animated:NO completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    [gear sendActionsForControlEvents:UIControlEventTouchUpInside];
    __block void (^step)(NSUInteger);
    step = ^(NSUInteger index) {
        Later(^{
            UIViewController *page = self.root.presentedViewController;
            UITableViewController *list = (id)MenuNavigation(page.presentedViewController).topViewController;
            if (index == 8 || (changedActions && index == 4)) {
                Check(!page && leafCalls == 1,@"a rebuilt submenu leaf must execute once and close the stack");
                [@"PASS: fresh owners after teardown, nested Back replay, root Back and exact-once leaf selection\n"
                    writeToFile:ResultPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
                step = nil; makePage = nil; return;
            }
            Check(list && YTKACEIsPlayerPopover(page.presentedViewController) && page.view.alpha == 0,
                @"every returned page must use the floating UI with a valid native model");
            Check(!TransitionCover(self.window),@"Back must settle without leaving a transition cover");
            if (changedActions && index == 3) {
                Check([page.title isEqual:@"Page 0"] && generations == 2 && leafCalls == 0,
                    @"changed actions must stop route replay at the fresh floating root without executing another row");
                [list.tableView.delegate tableView:list.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
                step(4); return;
            }
            if (index == 3 || index == 5) {
                Check([page.title isEqual:@"Page 1"] && generations == (index == 3 ? 2u : 3u),
                    @"nested Back must rebuild and replay only the route to the preceding page");
                for (NativeTestOwner *old in owners) if (old.native != page)
                    Check(old.actions == nil,@"dismissed owners must be torn down, never reused on Back");
            }
            if (index == 6) Check([page.title isEqual:@"Page 0"] && generations == 4,
                @"Back from the first submenu must rebuild a fresh gear root");
            if (index == 2 || index == 4 || index == 5) {
                UIBarButtonItem *back = list.navigationItem.leftBarButtonItem;
                Check(back != nil,@"nested menus must offer Back");
                [UIApplication.sharedApplication sendAction:back.action to:back.target from:back forEvent:nil];
                // A second tap during dismissal must not rebuild a second stack.
                [UIApplication.sharedApplication sendAction:back.action to:back.target from:back forEvent:nil];
            } else {
                NSUInteger row = index == 7 ? 1 : 0;
                [list.tableView.delegate tableView:list.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
            }
            step(index + 1);
        });
    };
    step(0);
}

#pragma clang diagnostic pop
- (void)testELMCommandOrder:(NSUInteger)mode {
    UIButton *gear = [UIButton buttonWithType:UIButtonTypeSystem];
    gear.frame = CGRectMake(240,140,44,44); [self.button.superview addSubview:gear];
    YTKACERegisterNativeGearMenuSource(gear);
    YTBottomSheetController *native = [YTBottomSheetController new];
    native.modalPresentationStyle = UIModalPresentationCustom; native.transitioningDelegate = self;
    YTDraggableView *panel = [[YTDraggableView alloc] initWithFrame:CGRectMake(8,80,320,180)];
    [native.view addSubview:panel];
    YTMenuItemElementsMDCButton *button = [[YTMenuItemElementsMDCButton alloc] initWithFrame:CGRectMake(0,0,320,56)];
    [panel addSubview:button];
    UIView *element = [[UIView alloc] initWithFrame:button.bounds]; [button addSubview:element];
    UIImage *arrow = [[UIImage systemImageNamed:@"chevron.right"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    UIImageView *trailing = [[UIImageView alloc] initWithImage:arrow];
    trailing.frame = CGRectMake(292,18,12,20); trailing.tintColor = UIColor.whiteColor;
    trailing.alpha = .6; [element addSubview:trailing];
    UIImageView *leading = [[UIImageView alloc] initWithImage:arrow];
    leading.frame = CGRectMake(16,18,12,20); leading.tintColor = UIColor.whiteColor; [element addSubview:leading];
    UIImageView *checkmark = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark"]];
    checkmark.frame = CGRectMake(270,18,18,20); checkmark.tintColor = UIColor.greenColor; [element addSubview:checkmark];
    UIImage *layerArrow = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(12,20)]
        imageWithActions:^(__unused UIGraphicsImageRendererContext *context) { [arrow drawInRect:CGRectMake(0,0,12,20)]; }];
    CALayer *accessory = [CALayer layer]; accessory.frame = CGRectMake(294,18,12,20);
    id originalContents = (__bridge id)layerArrow.CGImage;
    accessory.contents = originalContents; accessory.opacity = .6; [element.layer addSublayer:accessory];
    ELMTouchCommandPropertiesHandler *command = [ELMTouchCommandPropertiesHandler new];
    if (mode != 6) InstallELMTap(element,command,mode != 5);
    if (mode == 4) {
        UIView *accessory = [[UIView alloc] initWithFrame:CGRectMake(0,0,20,20)]; [element addSubview:accessory];
        InstallELMTap(accessory,[ELMTouchCommandPropertiesHandler new],YES);
    }
    GOODialogView *dialog = [GOODialogView new]; dialog.native = native;
    [button addTarget:dialog action:@selector(actionButtonDidTap:) forControlEvents:UIControlEventTouchUpInside];
    NativeTestAction *model = [NativeTestAction new]; model.button = button;
    model.shouldDismissOnAction = mode != 3;
    model.handler = ^{ Check(NO,@"an ELM content command must not invoke its placeholder model handler"); };
    __block NativeTestOwner *owner = [NativeTestOwner new]; owner.native = native; owner.actions = @[model];
    if (mode == 1) owner.dismissalDelay = 0.1;
    native.actionsController = owner;
    owner.clearsActionsOnDismiss = [NSProcessInfo.processInfo.arguments containsObject:@"--back-regression"];
    [gear addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
        owner.actions = @[model]; native.actionsController = owner;
        YTKACERememberPlayerMenuSource(gear);
        [self.root presentViewController:native animated:NO completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    __block NSUInteger completions = 0, leafCalls = 0;
    __block YTBottomSheetController *child;
    __weak UIViewController *weakNative = native;
    __weak NativeTestOwner *weakOwner = owner;
    __weak PlayerMenuSmoke *weak = self;
    __block NSTimeInterval selectedAt = 0;
    command.callback = ^{
        Check(NSProcessInfo.processInfo.systemUptime - selectedAt < .1,
            @"submenu commands must begin on selection without waiting for a separate popover dismissal");
        UIViewController *parent = weakNative;
        Check(parent.presentingViewController != nil &&
            (weakOwner.dismissals == 0 || ([NSProcessInfo.processInfo.arguments containsObject:@"--back-regression"] && command.calls == 2)) &&
            button.superview == panel && button.userInteractionEnabled && parent.view.alpha == 1 && (mode == 3 || parent.view.layer.mask != nil),
            @"handleTap must execute once with its node graph restored and owner still presented");
        Check(TransitionCover(weak.window) != nil,@"the outgoing menu must remain visible while native owners change");
        Check(trailing.image == arrow && [trailing.tintColor isEqual:UIColor.whiteColor] && fabs(trailing.alpha - .6) < .01,
            @"native arrow image/tint must be restored before the ELM command runs");
        Check(accessory.contents == originalContents && fabs(accessory.opacity - .6) < .01,
            @"AsyncDisplayKit accessory contents and opacity must be restored before native command dispatch");
        if (mode == 8) return; // A leaf command closes without requesting a child.
        child = [NSProcessInfo.processInfo.arguments containsObject:@"--other-controller-regression"]
            ? (id)[NativeSettingsPage new] : [YTBottomSheetController new];
        NativeTestAction *leaf = [NativeTestAction new]; leaf.title = @"ELM child leaf";
        leaf.handler = ^{ leafCalls++; };
        YTDraggableView *childPanel = [[YTDraggableView alloc] initWithFrame:CGRectMake(8,80,320,180)];
        [child.view addSubview:childPanel];
        leaf.button = [[YTMenuItemElementsMDCButton alloc] initWithFrame:CGRectMake(0,0,320,56)];
        [childPanel addSubview:leaf.button];
        NativeTestAction *divider = [NativeTestAction new];
        divider.button = [[YTMenuItemElementsMDCButton alloc] initWithFrame:CGRectMake(0,56,320,9)];
        divider.handler = ^{ Check(NO,@"a structural 9pt ELM row must never become a menu action"); };
        [childPanel addSubview:divider.button];
        NativeTestAction *delayed = [NativeTestAction new];
        delayed.button = [[YTMenuItemElementsMDCButton alloc] initWithFrame:CGRectMake(0,65,320,9)];
        delayed.handler = ^{}; [childPanel addSubview:delayed.button];
        child.lateGeometryButton = delayed.button;
        child.actions = @[leaf,divider,delayed];
        if (mode == 9 || mode == 10) {
            // A short row with a real command is not a decorative divider.
            NativeTestAction *compact = [NativeTestAction new]; compact.handler = ^{};
            compact.button = [[YTMenuItemElementsMDCButton alloc] initWithFrame:CGRectMake(0,74,320,9)];
            [childPanel addSubview:compact.button];
            if (mode == 9) InstallELMTap(compact.button,[ELMTouchCommandPropertiesHandler new],YES);
            else [compact.button addSubview:[UISwitch new]];
            child.actions = @[leaf,divider,delayed,compact];
        }
        dispatch_block_t present = ^{
            if (mode == 11 || mode == 12)
                Check(!weakNative.presentingViewController && weakOwner != nil,
                    @"late child requests must retain their dismissed source owner until presentation");
            UIViewController *presenter = (mode == 3 || mode == 7) ? weakNative : weak.root;
            [presenter presentViewController:child animated:YES completion:^{
                completions++;
                Check(mode == 3 ? weakNative.presentingViewController != nil : weakNative.presentingViewController == nil,
                    @"child presentation completion must follow the required source dismissal");
            }];
        };
        if (mode == 13)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500 * NSEC_PER_MSEC),dispatch_get_main_queue(),present);
        else if (mode == 11 || mode == 12)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350 * NSEC_PER_MSEC),dispatch_get_main_queue(),present);
        else if (mode == 1) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30 * NSEC_PER_MSEC),dispatch_get_main_queue(),present);
        else if (mode == 2) [weakOwner dismissViewControllerAnimated:NO completion:present];
        else present();
    };
    YTKACERememberPlayerMenuSource(gear);
    [self.root presentViewController:native animated:NO completion:nil];
    Later(^{
        UIViewController *menu = native.presentedViewController;
        if (mode == 4 || mode == 5) {
            Check(!menu && native.view.alpha == 1 && command.calls == 0 && dialog.closeCalls == 0,
                @"ambiguous or disabled ELM commands must preserve the native sheet without guessing a callback");
            [self.root dismissViewControllerAnimated:NO completion:^{
                [gear removeFromSuperview];
                if (mode == 4) [self testELMCommandOrder:5];
                else [@"PASS: ELM command-before-close, sync/async child requests, self-dismiss, retained-owner submenu, late gesture binding, exact-once leaf callbacks and unsupported-command fallback\n"
                    writeToFile:ResultPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }];
            return;
        }
        Check(YTKACEIsPlayerPopover(menu),@"ELM regression must start with the anchored gear replacement");
        Check(trailing.image.renderingMode == UIImageRenderingModeAlwaysTemplate &&
            [trailing.tintColor isEqual:UIColor.secondaryLabelColor] && trailing.alpha == 1,
            @"native right chevrons must share the metadata row's secondary label color");
        Check(accessory.contents && accessory.contents != originalContents && accessory.opacity == 1,
            @"layer-backed native chevrons must also receive the shared disclosure color and opacity");
        Check(leading.image == arrow && [leading.tintColor isEqual:UIColor.whiteColor] &&
            [checkmark.tintColor isEqual:UIColor.greenColor],@"leading glyphs and trailing checkmarks must keep their native styling");
        if (mode == 6) InstallELMTap(element,command,YES);
        UITableViewController *table = (id)MenuNavigation(menu).topViewController;
        selectedAt = NSProcessInfo.processInfo.systemUptime;
        [table.tableView.delegate tableView:table.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        [table.tableView.delegate tableView:table.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        if (mode == 12) { native.actionsController = nil; owner = nil; }
        if (mode == 13) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,400 * NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            Check(!weakNative.presentingViewController,@"fresh-touch history cancellation must occur after source dismissal");
            YTKACEUpdatePlayerMenuTouchSource(gear,self.window);
        });
        Later(^{
            if (mode == 8 || mode == 9 || mode == 10) {
                Check(command.calls == 1 && dialog.closeCalls == 0 && owner.dismissals == 1 &&
                    !TransitionCover(self.window),@"leaf/fallback paths must remove the transition cover without duplicate commands");
                if (mode == 8) {
                    Check(!self.root.presentedViewController && completions == 0,@"a leaf must close normally without waiting for a submenu");
                    [gear removeFromSuperview]; [self testELMCommandOrder:9];
                } else {
                    if (mode == 10) {
                        UIView *toggle = [((NativeTestAction *)child.actions.lastObject).button subviews].firstObject;
                        Check(YTKACEIsPlayerPopover(child.presentedViewController) && [toggle isKindOfClass:UISwitch.class] &&
                            [toggle isDescendantOfView:child.presentedViewController.view] && toggle.userInteractionEnabled,
                            @"a short native switch must remain live inside the shared content page");
                    } else Check(child.presentingViewController && !child.presentedViewController && child.view.alpha == 1,
                        @"an unsupported short command must retain its original native fallback");
                    [self.root dismissViewControllerAnimated:NO completion:^{
                        [gear removeFromSuperview]; [self testELMCommandOrder:mode == 9 ? 10 : 4];
                    }];
                }
                return;
            }
            Check(command.calls == 1 && dialog.closeCalls == 0 && completions == 1 &&
                weakOwner.dismissals == (mode == 3 ? 0u : 1u),
                @"ELM selection must dispatch the content command once and close through its owner at most once");
            Check(child && YTKACEIsPlayerPopover(child.presentedViewController) &&
                child.presentedViewController.popoverPresentationController.sourceView == self.window,
                @"ELM child must open visibly at the original gear anchor");
            Check(!TransitionCover(self.window),@"submenu slide must remove its transition cover after the new page appears");
            if (mode != 13) Check(child.presentedViewController == menu,
                @"gear and native child pages must reuse the same floating container instance");
            [table.tableView.delegate tableView:table.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
            Check(command.calls == 1 && ![[child.presentedViewController valueForKey:@"closing"] boolValue],
                @"a delayed tap on the retired page must not close or disable the reused container");
            Check(self.root.presentedViewController == (mode == 3 ? native : child),
                @"a dismissed source must not remain as an invisible parent of the child menu");
            UITableViewController *leaf = (id)MenuNavigation(child.presentedViewController).topViewController;
            Check([leaf.tableView.dataSource tableView:leaf.tableView numberOfRowsInSection:0] == 2,
                @"9pt structural row must be skipped only after layout, while the delayed 56pt row remains selectable");
            Check((leaf.navigationItem.leftBarButtonItem != nil) == (mode != 13),
                @"late children must offer Back, while a fresh player touch must invalidate the previous command's history");
            if ([NSProcessInfo.processInfo.arguments containsObject:@"--preview-late-child"]) {
                [@"ready" writeToFile:[ResultPath().stringByDeletingLastPathComponent stringByAppendingPathComponent:@"late-child-preview.txt"]
                    atomically:YES encoding:NSUTF8StringEncoding error:nil];
                return;
            }
            if ([NSProcessInfo.processInfo.arguments containsObject:@"--back-regression"]) {
                UIBarButtonItem *back = leaf.navigationItem.leftBarButtonItem;
                [UIApplication.sharedApplication sendAction:back.action to:back.target from:back forEvent:nil];
                Later(^{
                    Check(self.root.presentedViewController == native && YTKACEIsPlayerPopover(native.presentedViewController),
                        @"Back must reopen the preceding anchored native page");
                    Check(!native.view.layer.mask && native.view.alpha == 0 && leafCalls == 0,
                        @"Back must restore the previous page's rendering without executing a leaf action");
                    UITableViewController *parentList = (id)MenuNavigation(native.presentedViewController).topViewController;
                    selectedAt = NSProcessInfo.processInfo.systemUptime;
                    [parentList.tableView.delegate tableView:parentList.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
                    Later(^{
                        Check(command.calls == 2 && YTKACEIsPlayerPopover(child.presentedViewController),@"the returned parent must remain selectable and reopen its child");
                        UITableViewController *reopened = (id)MenuNavigation(child.presentedViewController).topViewController;
                        [reopened.tableView.delegate tableView:reopened.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
                        Later(^{
                            Check(leafCalls == 1 && !(mode == 3 ? child.presentingViewController : self.root.presentedViewController),
                                @"reopened child selection must execute once and honor the native owner's retention policy");
                            [@"PASS: submenu Back, parent reentry and exact-once reopened leaf selection\n"
                                writeToFile:ResultPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
                        });
                    });
                });
                return;
            }
            [leaf.tableView.delegate tableView:leaf.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
            Later(^{
                Check(leafCalls == 1 && !child.presentingViewController,
                    @"the child leaf must remain selectable and close exactly once");
                dispatch_block_t next = ^{
                    [gear removeFromSuperview];
                    [self testELMCommandOrder:mode == 3 ? 6 : (mode == 6 ? 7 : (mode == 7 ? 11 : (mode == 11 ? 12 : (mode == 12 ? 13 : (mode == 13 ? 8 : mode + 1)))))];
                };
                if (self.root.presentedViewController) [self.root dismissViewControllerAnimated:NO completion:next];
                else next();
            });
        });
    });
}
- (void)testNativeActivation:(NSUInteger)mode {
    UIButton *gear = self.button;
    // Use an actual native gear source rather than the tweak-only extraction path.
    gear = [UIButton buttonWithType:UIButtonTypeSystem];
    gear.frame = CGRectMake(240,140,44,44); [self.button.superview addSubview:gear];
    YTKACERegisterNativeGearMenuSource(gear);
    YTBottomSheetController *native = [YTBottomSheetController new];
    native.modalPresentationStyle = UIModalPresentationCustom; native.transitioningDelegate = self;
    YTDraggableView *panel = [[YTDraggableView alloc] initWithFrame:CGRectMake(8,80,320,120)];
    [native.view addSubview:panel];
    YTMenuItemElementsMDCButton *button = [[YTMenuItemElementsMDCButton alloc] initWithFrame:CGRectMake(0,0,320,56)];
    [panel addSubview:button];
    NativeTestAction *model = [NativeTestAction new]; model.button = button;
    NativeTestOwner *owner = [NativeTestOwner new]; owner.native = native; owner.actions = @[model];
    native.actionsController = owner;
    __block NSUInteger calls = 0;
    __block NSTimeInterval selectedAt = 0;
    __weak UIViewController *weakNative = native;
    dispatch_block_t navigate = ^{
        Check(NSProcessInfo.processInfo.systemUptime - selectedAt < .1,
            @"native submenu handlers must start without waiting for the outgoing popover dismissal");
        UIViewController *parent = weakNative;
        Check(parent.presentingViewController != nil && owner.dismissals == 0,
            @"native navigation must run before the native owner is dismissed");
        Check(button.superview == panel && button.userInteractionEnabled && parent.view.alpha == 1,
            @"native controls must be restored before their original activation");
        calls++;
        YTBottomSheetController *child = [YTBottomSheetController new];
        NativeTestAction *leaf = [NativeTestAction new]; leaf.title = @"Native child"; leaf.handler = ^{};
        child.actions = @[leaf];
        [parent presentViewController:child animated:YES completion:nil];
    };
    NativePassiveTarget *passiveA = [NativePassiveTarget new], *passiveB = [NativePassiveTarget new];
    if (mode == 0) {
        model.handler = ^{ Check(NO,@"placeholder model handler must not replace a registered ELM control event"); };
        [button addAction:[UIAction actionWithHandler:^(__unused UIAction *action) { navigate(); }]
            forControlEvents:UIControlEventTouchUpInside];
    } else if (mode == 1) {
        model.shouldDismissOnAction = NO; model.handler = navigate;
    } else {
        model.handler = ^{ Check(NO,@"diagnostics must not switch to the model handler after a passive native control event"); };
        [button addTarget:passiveA action:@selector(inkTap:) forControlEvents:UIControlEventTouchUpInside];
        [button addTarget:passiveB action:@selector(inkTap:) forControlEvents:UIControlEventTouchUpInside];
        [button addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
            Check(NO,@"diagnostics must not dispatch an extra primary-action event");
        }] forControlEvents:UIControlEventPrimaryActionTriggered];
    }
    YTKACERememberPlayerMenuSource(gear);
    [self.root presentViewController:native animated:NO completion:nil];
    Later(^{
        UIViewController *menu = native.presentedViewController;
        Check(YTKACEIsPlayerPopover(menu),@"native activation fixture must open an adapted gear menu");
        UITableViewController *table = (id)MenuNavigation(menu).topViewController;
        selectedAt = NSProcessInfo.processInfo.systemUptime;
        [table.tableView.delegate tableView:table.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        Later(^{
            UIViewController *child = native.presentedViewController;
            if (mode < 2) Check(calls == 1 && child && YTKACEIsPlayerPopover(child.presentedViewController),
                @"native activation must run once and anchor a child presented by the retained native owner");
            else Check(calls == 0 && !child && passiveA.calls == 1 && passiveB.calls == 1 &&
                self.root.presentedViewController == native && owner.dismissals == 0,
                @"diagnostics must observe two passive callbacks without inventing navigation or changing owner lifetime");
            [self.root dismissViewControllerAnimated:NO completion:^{
                [gear removeFromSuperview];
                if (mode < 2) [self testNativeActivation:mode + 1];
                else [@"PASS: traced UIAction/model navigation and passive two-target dispatch; no extra callback, event or owner teardown\n"
                    writeToFile:ResultPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }];
        });
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
    NativeTestAction *spacer = [NativeTestAction new]; spacer.button = [[YTSpacerButton alloc] initWithFrame:CGRectMake(0,0,386,1)];
    spacer.handler = ^(__unused id sender) { Check(NO,@"a one-point spacer placeholder must never execute"); };
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
        NativeTestAction *spacer = [NativeTestAction new]; spacer.button = [[YTSpacerButton alloc] initWithFrame:CGRectMake(0,0,386,1)];
    spacer.handler = ^(__unused id sender) { Check(NO,@"a one-point spacer placeholder must never execute"); };
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
    YTDraggableView *panel = [[YTDraggableView alloc] initWithFrame:CGRectMake(8,80,398,256)];
    [native.view addSubview:panel];
    NativeOriginAction *model = [NativeOriginAction new]; model.handler = handler;
    NativeTestOpaqueButton *button = [[NativeTestOpaqueButton alloc] initWithFrame:CGRectMake(0,0,398,56)];
    button.opaque = NO; button.backgroundColor = UIColor.clearColor;
    [panel addSubview:button]; model.button = button;
    NSMutableArray *models = [NSMutableArray arrayWithObject:model];
    for (NSUInteger index = 1; index <= 4; ++index) {
        NativeOriginAction *item = [NativeOriginAction new]; item.handler = ^{ Check(NO,@"unselected native row handler must not run"); };
        NativeTestOpaqueButton *row = [[NativeTestOpaqueButton alloc] initWithFrame:CGRectMake(0,MIN(index,3u) * 56,398,index < 3 ? 56 : -0.0)];
        [panel addSubview:row]; item.button = row; [models addObject:item];
        if (index == 4) native.lateGeometryButton = row;
    }
    // Match the real device: index 3 remains collapsed in the action array,
    // while index 4 gains native geometry asynchronously after presentation.
    NativeTestAction *spacer = [NativeTestAction new]; spacer.button = [[YTSpacerButton alloc] initWithFrame:CGRectMake(0,224,398,1)];
    spacer.handler = ^(__unused id sender) { Check(NO,@"native gear spacer placeholders are structural"); };
    [panel addSubview:spacer.button];
    [models addObject:spacer];
    YTActionSheetAction *extension = [YTActionSheetAction actionWithTitle:@"字幕動態島"
        iconImage:[UIImage systemImageNamed:@"captions.bubble"] style:0 handler:nil];
    extension.handler = ^{ GearExtensionCalls++; handler(); };
    [models addObject:extension];
    NativeTestOwner *owner = [NativeTestOwner new]; owner.native = native; owner.actions = models;
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
        Check([table.tableView numberOfRowsInSection:0] == 5,
            @"the gear must combine four live rows and a metadata-only extension after omitting the collapsed row");
        NSIndexPath *extensionIndex = [NSIndexPath indexPathForRow:4 inSection:0];
        UITableViewCell *extensionCell = [table.tableView.dataSource tableView:table.tableView cellForRowAtIndexPath:extensionIndex];
        Check([extensionCell.textLabel.text isEqual:@"字幕動態島"] && extensionCell.imageView.image != nil,
            @"the metadata-only extension must retain its captured title and icon");
        UIView *collapsedRow = [(NativeTestAction *)[(NativeTestOwner *)self.gearNative.actionsController actions][3] button];
        Check(self.gearNative.lateGeometryButton.superview != collapsedRow.superview,
            @"the late row must be borrowed while the collapsed row stays in the native hierarchy");
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--preview-native-gear"]) {
            [@"READY: hidden native gear anchored to window rect" writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/gear-preview.txt"]
                atomically:YES encoding:NSUTF8StringEncoding error:nil]; return;
        }
        if (!self.gearRound) [menu dismissViewControllerAnimated:NO completion:nil];
        else [table.tableView.delegate tableView:table.tableView didSelectRowAtIndexPath:extensionIndex];
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
                Check(!self.root.presentedViewController && self.gearCallbacks == 1 && self.gearChildCallbacks == 1 && GearExtensionCalls == 1,
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
            [@"PASS: zero-height and delayed native gear rows, native gear and submenu popovers, hidden-gear window anchors, live native rows without title reads, repeat cancel/select/owner lifecycle, tweak routing, bounds, scrolling, settings and rotation\n"
                writeToFile:ResultPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }];
    });
}
@end

int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(PlayerMenuSmoke.class)); }
}
