#import <UIKit/UIKit.h>
#import "../../Tweak/UI/OverlayButtonHost.h"
#import "../../Tweak/UI/PlayerMenuPresentation.h"
#import "../../Tweak/Runtime/Preferences.h"
#import "../../Tweak/Runtime/Localization.h"
#import "../../Tweak/Features/Downloads/DownloadLog.h"
#import "../../Tweak/YTKACE.h"
#import "../../Tweak/UI/Notice.h"
#import "../../Tweak/Features/Playback/QualityControls.h"
#import <objc/message.h>
#include <cmath>

NSString * const YTKACEPreferencesDidChangeNotification = @"YTKACEPreferencesDidChange";
static BOOL KeepControls = YES, HiddenFeatures = NO, ReenterLayout = NO;
static BOOL GlassEnabled = YES, ReenterGlass = NO;
static NSUInteger NativeLayouts;
BOOL YTKACEFeatureEnabled(NSString *key) {
    if ([key hasSuffix:@"AlwaysShowControls"]) return KeepControls;
    if ([key isEqual:@"YTKACE.Preference.Glass.Player"]) return GlassEnabled;
    if ([key isEqual:@"YTKACE.Preference.Playback.QualityButton"]) return !HiddenFeatures;
    return YES;
}
BOOL YTKACELiquidGlassAvailable(void) { return NSClassFromString(@"UIGlassEffect") != nil; }
NSString *YTKACELocalized(NSString *key) { return key; }
void YTKACEDownloadLog(NSString *key, NSString *format, ...) { (void)key; (void)format; }
void YTKACEShowNotice(NSString *message) { (void)message; }

@interface QualityTestPlayer : NSObject
@property(nonatomic, strong) id activeVideo;
@end
@implementation QualityTestPlayer
@end
@interface QualityTestPresenter : NSObject
@property(nonatomic) NSUInteger calls;
- (void)didPressVideoQuality:(id)sender;
@end
@implementation QualityTestPresenter
- (void)didPressVideoQuality:(id)sender { (void)sender; self.calls++; }
@end
@interface QualityTestFormat : NSObject
@property(nonatomic, copy) NSString *qualityLabel;
@end
@implementation QualityTestFormat
@end
@interface YTVideoQualitySwitchOriginalController : NSObject
- (void)singleVideo:(id)video didSelectVideoFormat:(id)format;
@end
@implementation YTVideoQualitySwitchOriginalController
- (void)singleVideo:(id)video didSelectVideoFormat:(id)format { (void)video; (void)format; }
@end

@interface YTMainAppControlsOverlayView : UIView
@property(nonatomic, getter=isOverlayVisible) BOOL overlayVisible;
@property(nonatomic, strong) UIButton *overflowButton;
@property(nonatomic) BOOL requestedVisible;
@property(nonatomic, strong) id playerViewController;
@property(nonatomic, strong) id eventsDelegate;
@end
@implementation YTMainAppControlsOverlayView
- (void)layoutSubviews {
    NativeLayouts++;
    if (ReenterLayout) [self layoutSubviews];
    [super layoutSubviews];
}
- (void)setOverlayVisible:(BOOL)visible { _overlayVisible = visible; self.requestedVisible = visible; }
@end
@interface YTMainAppVideoPlayerOverlayView : UIView
@end
@implementation YTMainAppVideoPlayerOverlayView
@end
@interface TestPan : UIPanGestureRecognizer
@property(nonatomic) UIGestureRecognizerState testState;
@end
@implementation TestPan
- (UIGestureRecognizerState)state { return self.testState; }
@end
@interface YTFrostedGlassView : UIView
@property(nonatomic, strong) UIVisualEffectView *_blurEffectView;
@property(nonatomic, strong) UIView *_overlayView;
@end
@implementation YTFrostedGlassView
- (void)layoutSubviews {
    if (ReenterGlass) [self layoutSubviews];
    [super layoutSubviews];
}
@end
@interface TestActionTarget : NSObject
@property(nonatomic, weak) UIView *overlay;
@property(nonatomic, weak) UIButton *button;
@property(nonatomic) NSUInteger calls;
- (void)tap:(UIButton *)sender;
@end
@implementation TestActionTarget
- (void)tap:(UIButton *)sender { (void)sender; self.calls++; }
@end

static NSString *ResultPath(void) { return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/result.txt"]; }
static void Check(BOOL ok, NSString *message) {
    if (ok) return;
    [[@"FAIL: " stringByAppendingString:message] writeToFile:ResultPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    abort();
}
static UIStackView *Row(UIView *overlay) {
    for (UIView *child in overlay.subviews) if ([child.accessibilityIdentifier isEqual:@"YTKACEOverlayControls"]) return (id)child;
    return nil;
}
static UIButton *More(UIStackView *row) {
    for (UIStackView *candidate in row.superview.subviews) {
        if (![candidate isKindOfClass:UIStackView.class]) continue;
        for (UIButton *button in candidate.arrangedSubviews) if ([button.accessibilityIdentifier isEqual:@"YTKACE More Player Controls"]) return button;
    }
    return nil;
}
static BOOL Finite(CGRect r) { return std::isfinite(r.origin.x) && std::isfinite(r.origin.y) && std::isfinite(r.size.width) && std::isfinite(r.size.height); }

@interface PlayerControlsSmoke : UIResponder <UIApplicationDelegate, UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation PlayerControlsSmoke
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options { (void)app; (void)options; return YES; }
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)app; (void)options;
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];
    config.delegateClass = self.class; return config;
}
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [UIViewController new]; [self.window makeKeyAndVisible];
    // Allow the initial scene appearance transition to finish before exercising
    // the explicit interactive-transition scenarios below.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self runTests]; });
}
- (void)runTests {
    YTKACEInstallPlayerMenuPresentation();
    YTKACEInstallQualityControls();
    TestActionTarget *target = [TestActionTarget new];
    YTKACERegisterOverlayConfigurator(@"test-controls", ^(UIView *overlay, UIStackView *stack) {
        target.overlay = overlay;
        for (int index = 0; index < 8; ++index) {
            UIButton *button = YTKACEOverlayButton(stack, [NSString stringWithFormat:@"YTKACE Test %d", index], @"play", target, @selector(tap:));
            button.hidden = HiddenFeatures;
            target.button = button;
        }
    });
    YTMainAppVideoPlayerOverlayView *player = [[YTMainAppVideoPlayerOverlayView alloc] initWithFrame:CGRectMake(0, 80, 414, 233)];
    YTMainAppControlsOverlayView *overlay = [[YTMainAppControlsOverlayView alloc] initWithFrame:player.bounds];
    overlay.overlayVisible = YES;
    QualityTestPlayer *qualityPlayer = [QualityTestPlayer new]; qualityPlayer.activeVideo = [NSObject new];
    QualityTestPresenter *qualityPresenter = [QualityTestPresenter new];
    overlay.playerViewController = qualityPlayer; overlay.eventsDelegate = qualityPresenter;
    [self.window.rootViewController.view addSubview:player]; [player addSubview:overlay];
    NSMutableArray<UIButton *> *native = [NSMutableArray array];
    for (NSNumber *x in @[@8, @258, @308, @358]) {
        UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(x.doubleValue, 4, 44, 44)];
        [native addObject:button]; [overlay addSubview:button];
    }
    overlay.overflowButton = native.lastObject;
    for (NSNumber *x in @[@85, @178, @275]) {
        UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(x.doubleValue, 90, 60, 60)];
        [overlay addSubview:button];
    }
    [overlay layoutSubviews];
    UIStackView *row = Row(overlay);
    Check(row && !row.hidden && row.alpha == 1 && row.frame.origin.y == 4, @"portrait controls must appear in the native top band without YTVideoOverlay");
    UIButton *more = More(row);
    UIStackView *second = nil;
    for (UIView *view in overlay.subviews) if ([view.accessibilityIdentifier isEqual:@"YTKACEOverlayControls.SecondRow"]) second = (id)view;
    Check(second && !second.hidden && second.frame.origin.y == 54, @"overflow must use the next row below the native gear");
    Check(more && !more.hidden && more.menu.children.count > 0, @"portrait overflow must remain accessible");
    Check(CGRectContainsRect(overlay.bounds, row.frame), @"portrait controls must stay within the player");
    for (UIButton *button in native) Check(!CGRectIntersectsRect(row.frame, button.frame), @"native controls must remain unobstructed");
    CGRect firstBeforeFade = row.frame, secondBeforeFade = second.frame;
    KeepControls = NO;
    for (NSNumber *alpha in @[@0.8,@0.3,@0.0,@0.4]) {
        for (UIButton *button in native) button.alpha = alpha.doubleValue;
        [overlay layoutSubviews];
        Check(CGRectEqualToRect(row.frame,firstBeforeFade) && CGRectEqualToRect(second.frame,secondBeforeFade), @"faded native controls must retain their reserved positions");
    }
    [overlay setOverlayVisible:NO]; [overlay layoutSubviews];
    Check(CGRectEqualToRect(row.frame,firstBeforeFade), @"auto-hidden controls must not pack over native buttons");
    for (UIButton *button in native) button.alpha = 1;
    [overlay setOverlayVisible:YES]; [overlay layoutSubviews]; KeepControls = YES;
    [row layoutIfNeeded];
    for (UIButton *button in row.arrangedSubviews) if (!button.hidden) Check(button.bounds.size.width >= 44, @"readable controls retain touch size");
    NSUInteger before = NativeLayouts;
    ReenterLayout = YES; [overlay layoutSubviews]; ReenterLayout = NO;
    Check(NativeLayouts == before + 1, @"layout recursion must be bounded");
    for (int i = 0; i < 30; ++i) [overlay layoutSubviews];
    Check(!row.hidden && More(row) == more, @"repeated layout must preserve the local row and overflow identity");
    HiddenFeatures = YES; [overlay layoutSubviews]; Check(row.hidden, @"feature gates");
    HiddenFeatures = NO; [overlay layoutSubviews]; Check(!row.hidden, @"restore feature controls");
    [overlay setOverlayVisible:NO]; Check(overlay.requestedVisible, @"keep-controls preference outside transitions");
    TestPan *pan = [TestPan new]; [player addGestureRecognizer:pan]; pan.testState = UIGestureRecognizerStateChanged;
    [overlay setOverlayVisible:NO]; Check(!overlay.requestedVisible, @"native exit gesture must be allowed to hide controls");
    [overlay layoutSubviews]; Check(row.hidden, @"defer local layout during interactive pan");
    pan.testState = UIGestureRecognizerStateCancelled;
    [overlay setOverlayVisible:YES]; [overlay layoutSubviews]; Check(!row.hidden, @"cancelled pan must recover controls");
    CGRect valid = row.frame;
    player.transform = CGAffineTransformMakeScale(0, 0);
    [overlay layoutSubviews]; Check(row.hidden && CGRectEqualToRect(row.frame, valid), @"singular transition must not write invalid geometry");
    player.transform = CGAffineTransformIdentity;
    [overlay layoutSubviews]; Check(!row.hidden && Finite(row.frame), @"valid geometry must restore controls");
    overlay.frame = CGRectMake(0, 0, 852, 414); player.frame = CGRectMake(0, 0, 852, 414);
    native[1].frame = CGRectMake(696,4,44,44); native[2].frame = CGRectMake(746,4,44,44); native[3].frame = CGRectMake(796,4,44,44);
    [overlay layoutSubviews];
    Check(!row.hidden && more.hidden && row.frame.origin.y == 4, @"landscape must restore all inline controls");
    for (UIButton *button in row.arrangedSubviews) if (button != more) Check(!button.hidden, @"landscape button visibility");
    overlay.frame = CGRectMake(0,0,414,233); player.frame = CGRectMake(0,80,414,233);
    native[1].frame = CGRectMake(258,4,44,44); native[2].frame = CGRectMake(308,4,44,44); native[3].frame = CGRectMake(358,4,44,44);
    [overlay layoutSubviews]; Check(!row.hidden && !more.hidden, @"fullscreen exit must restore portrait row");
    UIButton *button = nil, *qualityButton = nil;
    for (UIStackView *candidate in @[row,second]) for (UIButton *item in candidate.arrangedSubviews) {
        if ([item.accessibilityIdentifier isEqual:@"YTKACE Test 0"]) button = item;
        if ([item.accessibilityIdentifier isEqual:@"YTKACE Quality"]) qualityButton = item;
    }
    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
    Check(target.calls == 1 && target.overlay == overlay, @"local actions keep player context");
    Check(qualityButton && [qualityButton.currentTitle isEqual:@"Auto"], @"integrated quality button default");
    QualityTestFormat *format = [QualityTestFormat new]; format.qualityLabel = @"1080p60 HDR";
    [[YTVideoQualitySwitchOriginalController new] singleVideo:qualityPlayer.activeVideo didSelectVideoFormat:format];
    [overlay layoutSubviews];
    Check([qualityButton.currentTitle isEqual:@"1080p"] && [qualityButton.accessibilityValue isEqual:@"1080p60 HDR"], @"selected quality must update label and retain full accessibility value");
    [qualityButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    Check(qualityPresenter.calls == 1, @"quality shortcut must open the native quality selector once");
    qualityPlayer.activeVideo = [NSObject new]; [overlay layoutSubviews];
    Check([qualityButton.currentTitle isEqual:@"Auto"], @"quality label must not leak to another video");
    Check([YTKACEQualityButtonTitle(@"2160p60 HDR") isEqual:@"4K"] && [YTKACEQualityButtonTitle(@"1440p") isEqual:@"2K"], @"compact high-resolution labels");

    // Exercise the actual PlayerGlass hook with the user's reported settings:
    // keep-controls off, player glass on, and both button/gesture transitions.
    KeepControls = NO;
    YTFrostedGlassView *frosted = [[YTFrostedGlassView alloc] initWithFrame:CGRectMake(60,180,56,56)];
    frosted._blurEffectView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    frosted._blurEffectView.alpha = 0.65;
    frosted._overlayView = [UIView new]; frosted._overlayView.alpha = 0.4;
    [frosted addSubview:frosted._blurEffectView]; [frosted addSubview:frosted._overlayView];
    [overlay addSubview:frosted]; [frosted layoutSubviews];
    UIVisualEffectView *glass = nil;
    for (UIView *child in frosted.subviews) if ([child isKindOfClass:UIVisualEffectView.class] && child != frosted._blurEffectView) glass = (id)child;
    Check(glass && !glass.hidden, @"player glass enabled on a stable control");
    NSUInteger surfaces = frosted.subviews.count;
    ReenterGlass = YES; [frosted layoutSubviews]; ReenterGlass = NO;
    for (int i = 0; i < 20; ++i) [frosted layoutSubviews];
    Check(frosted.subviews.count == surfaces && Finite(glass.frame), @"glass layout must be bounded, stable and reuse one surface");
    for (int i = 0; i < 8; ++i) {
        player.transform = CGAffineTransformMakeScale(0.8,0.8);
        [frosted layoutSubviews];
        Check(glass.hidden && fabs(frosted._blurEffectView.alpha - 0.65) < 0.001, @"button-driven transform must yield to native glass");
        player.transform = CGAffineTransformIdentity;
        [frosted layoutSubviews]; Check(!glass.hidden, @"glass must recover after a completed/cancelled transition");
    }
    pan.testState = UIGestureRecognizerStateChanged;
    [frosted layoutSubviews]; Check(glass.hidden, @"glass must defer interactive exit");
    pan.testState = UIGestureRecognizerStateEnded;
    frosted.bounds = CGRectZero; [frosted layoutSubviews]; Check(glass.hidden, @"zero-sized glass must not render");
    frosted.bounds = CGRectMake(0,0,56,56);
    [frosted layoutSubviews]; Check(!glass.hidden, @"glass must recover from zero size");
    Class effectClass = NSClassFromString(@"UIGlassEffect");
    frosted._blurEffectView.effect = ((id (*)(id, SEL, NSInteger))objc_msgSend)(effectClass, NSSelectorFromString(@"effectWithStyle:"), 0);
    [frosted layoutSubviews];
    Check(glass.hidden && frosted._blurEffectView.alpha > 0, @"reuse native Liquid Glass without another overlay");
    GlassEnabled = NO; [frosted layoutSubviews];
    Check(fabs(frosted._overlayView.alpha - 0.4) < 0.001, @"restore exact native overlay alpha");
    [@"PASS: standalone portrait/fullscreen controls, overflow, feature gates, bounded reentry, exit transitions, geometry recovery, actions and PlayerGlass lifecycle" writeToFile:ResultPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
@end
int main(int argc, char **argv) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(PlayerControlsSmoke.class)); } }
