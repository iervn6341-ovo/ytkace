#import <UIKit/UIKit.h>
#import "../../Tweak/UI/SystemMenu.h"
#import "../../Tweak/UI/PlayerMenuPresentation.h"
#import "../../Tweak/Runtime/Preferences.h"
#import "../../Tweak/Runtime/Localization.h"
#import "../../Tweak/Features/Downloads/DownloadLog.h"

static BOOL Features = YES;
NSString * const YTKACEPreferencesDidChangeNotification = @"YTKACEPreferencesDidChange";
BOOL YTKACEFeatureEnabled(NSString *key) { (void)key; return Features; }
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
@interface YTBottomSheetController : UIViewController @end
@implementation YTBottomSheetController @end

static UINavigationController *MenuNavigation(UIViewController *presentation) {
    return [presentation isKindOfClass:UINavigationController.class] ? (id)presentation : (id)presentation.childViewControllers.firstObject;
}
@interface PlayerMenuSmoke : UIResponder <UIApplicationDelegate, UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) UIViewController *root;
@property(nonatomic, strong) UIButton *button;
@property(nonatomic) NSInteger callbacks;
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
    [self.window makeKeyAndVisible];
    Later(^{ [self testOwnedMenu]; });
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
- (void)testSettingsScope {
    UIButton *settings = [UIButton buttonWithType:UIButtonTypeSystem];
    settings.frame = CGRectMake(20, 160, 100, 44);
    [self.root.view addSubview:settings]; // Outside the player overlay.
    Check(YTKACEPresentSystemMenu(self.root, settings, @"Settings", nil, self.actions), @"settings did not present");
    Later(^{
        UIViewController *menu = self.root.presentedViewController;
        Check(!YTKACEIsPlayerPopover(menu), @"settings incorrectly became a player popover");
        UINavigationController *navigation = MenuNavigation(menu);
        UITableViewController *table = (id)navigation.topViewController;
        CGFloat slack = table.tableView.bounds.size.height - table.tableView.contentSize.height -
            table.tableView.contentInset.top - table.tableView.contentInset.bottom;
        Check(slack < 48, @"short settings sheet has excessive blank footer");
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
            [self.button addTarget:self action:@selector(openNative:) forControlEvents:UIControlEventTouchUpInside];
            [self.button sendActionsForControlEvents:UIControlEventTouchUpInside];
            Later(^{ [self verifyNative]; });
        }];
    });
}
- (void)openNative:(UIButton *)sender {
    (void)sender;
    UIViewController *native = [YTBottomSheetController new];
    native.modalPresentationStyle = UIModalPresentationPageSheet;
    [self.root presentViewController:native animated:NO completion:nil];
}
- (void)verifyNative {
    UIViewController *native = self.root.presentedViewController;
    Check(YTKACEIsPlayerPopover(native) && native.popoverPresentationController.sourceView == self.button,
        @"native sheet was not routed to the tapped player button");
    [native dismissViewControllerAnimated:NO completion:^{
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
    }];
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
        [@"PASS: compact popover, bounds, selection, disabled actions, dismissal ordering, long-list scrolling, native routing, settings scope, feature toggle and landscape rotation\n"
            writeToFile:ResultPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }); });
}
@end

int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(PlayerMenuSmoke.class)); }
}
