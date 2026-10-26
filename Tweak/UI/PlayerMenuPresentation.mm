#import "PlayerMenuPresentation.h"
#import "OverlayButtonHost.h"
#import "../Runtime/Hooking.h"
#import "../Runtime/Preferences.h"
#import <objc/runtime.h>

static const void *PopoverKey = &PopoverKey;
static const void *TapKey = &TapKey;
static IMP OriginalSendAction, OriginalPresent;

@interface YTKACEPlayerMenuTap : NSObject
@property(nonatomic, weak) UIView *source;
@property(nonatomic) NSTimeInterval uptime;
@property(nonatomic, weak) UIViewController *menu;
@end
@implementation YTKACEPlayerMenuTap
@end

static BOOL VisibleSource(UIView *source, UIWindow *window) {
    if (!source || !window || source.window != window || CGRectIsEmpty(source.bounds)) return NO;
    for (UIView *view = source; view; view = view.superview)
        if (view.hidden || view.alpha < 0.05) return NO;
    CGRect visible = CGRectIntersection([source convertRect:source.bounds toView:window],
        UIEdgeInsetsInsetRect(window.bounds, window.safeAreaInsets));
    return !CGRectIsNull(visible) && !CGRectIsEmpty(visible);
}

BOOL YTKACEIsPlayerMenuSource(UIView *source) {
    if (!VisibleSource(source, source.window)) return NO;
    for (UIView *view = source; view; view = view.superview) {
        for (NSString *name in @[@"YTMainAppControlsOverlayView", @"YTMainAppVideoPlayerOverlayView",
                                 @"YTInlinePlayerBarContainerView", @"YTPlayerView"]) {
            Class cls = NSClassFromString(name);
            if (cls && [view isKindOfClass:cls]) return YES;
        }
    }
    return NO;
}

static BOOL Enabled(void) {
    return YTKACEFeatureEnabled(@"YTKACE.Preference.Interface.SystemMenus");
}

void YTKACERememberPlayerMenuSource(UIView *source) {
    if (!Enabled() || !YTKACEIsPlayerMenuSource(source)) return;
    YTKACEPlayerMenuTap *tap = [YTKACEPlayerMenuTap new];
    tap.source = source;
    tap.uptime = NSProcessInfo.processInfo.systemUptime;
    objc_setAssociatedObject(source.window, TapKey, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static CGSize BoundedSize(UIWindow *window, CGSize size) {
    CGRect safe = UIEdgeInsetsInsetRect(window.bounds, window.safeAreaInsets);
    return CGSizeMake(MIN(MAX(160.0, size.width), MAX(160.0, safe.size.width - 24)),
                      MIN(MAX(88.0, size.height), MAX(88.0, safe.size.height - 24)));
}

@interface YTKACEPlayerPopoverDelegate : NSObject <UIPopoverPresentationControllerDelegate>
@property(nonatomic, weak) UIView *source;
@end
@implementation YTKACEPlayerPopoverDelegate
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller {
    (void)controller; return UIModalPresentationNone;
}
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller
                                                               traitCollection:(UITraitCollection *)traits {
    (void)controller; (void)traits; return UIModalPresentationNone;
}
- (void)popoverPresentationController:(UIPopoverPresentationController *)popover
         willRepositionPopoverToRect:(inout CGRect *)rect inView:(inout UIView **)view {
    UIView *source = self.source;
    UIWindow *window = popover.presentingViewController.view.window;
    if (!VisibleSource(source, window)) {
        [popover.presentedViewController dismissViewControllerAnimated:NO completion:nil];
        return;
    }
    *view = source;
    *rect = source.bounds;
    popover.presentedViewController.preferredContentSize = BoundedSize(window,
        popover.presentedViewController.preferredContentSize);
}
@end

BOOL YTKACEIsPlayerPopover(UIViewController *controller) {
    return objc_getAssociatedObject(controller, PopoverKey) != nil;
}

BOOL YTKACEConfigurePlayerPopover(UIViewController *controller, UIViewController *presenter,
                                   UIView *source, CGSize size) {
    if (!NSThread.isMainThread || !Enabled() || !YTKACEIsPlayerMenuSource(source) ||
        !VisibleSource(source, presenter.view.window)) return NO;
    UIModalPresentationStyle originalStyle = controller.modalPresentationStyle;
    id<UIViewControllerTransitioningDelegate> originalTransition = controller.transitioningDelegate;
    controller.modalPresentationStyle = UIModalPresentationPopover;
    UIPopoverPresentationController *popover = controller.popoverPresentationController;
    if (!popover) {
        controller.modalPresentationStyle = originalStyle;
        controller.transitioningDelegate = originalTransition;
        return NO;
    }
    controller.transitioningDelegate = nil;
    controller.preferredContentSize = BoundedSize(source.window, size);
    YTKACEPlayerPopoverDelegate *delegate = [YTKACEPlayerPopoverDelegate new];
    delegate.source = source;
    // UIKit holds its delegate weakly. Retain it with the presented controller.
    objc_setAssociatedObject(controller, PopoverKey, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    popover.delegate = delegate;
    popover.sourceView = source;
    popover.sourceRect = source.bounds;
    popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    popover.passthroughViews = nil;
    YTKACERememberPlayerMenuSource(source);
    YTKACEPlayerMenuTap *tap = objc_getAssociatedObject(source.window, TapKey);
    tap.menu = controller;
    return YES;
}

static BOOL IsYouTubeMenu(UIViewController *controller) {
    UIViewController *content = [controller isKindOfClass:UINavigationController.class]
        ? ((UINavigationController *)controller).topViewController : controller;
    for (NSString *name in @[@"YTBottomSheetController", @"YTContextualSheetViewController",
                             @"YTActionSheetDialogViewController"]) {
        Class cls = NSClassFromString(name);
        if (cls && [content isKindOfClass:cls]) return YES;
    }
    return NO;
}

static UIView *SourceForPresenter(UIViewController *presenter) {
    UIViewController *ancestor = presenter;
    for (NSUInteger depth = 0; ancestor && depth < 12; ++depth) {
        YTKACEPlayerPopoverDelegate *delegate = objc_getAssociatedObject(ancestor, PopoverKey);
        if (VisibleSource(delegate.source, presenter.view.window)) return delegate.source;
        ancestor = ancestor.parentViewController ?: ancestor.presentingViewController;
    }
    YTKACEPlayerMenuTap *tap = objc_getAssociatedObject(presenter.view.window, TapKey);
    BOOL activeMenu = tap.menu.presentingViewController != nil || tap.menu.isBeingDismissed;
    if (tap && (activeMenu || NSProcessInfo.processInfo.systemUptime - tap.uptime <= 1.5) &&
        [tap.source isDescendantOfView:presenter.view] &&
        VisibleSource(tap.source, presenter.view.window)) return tap.source;
    return nil;
}

static void SendAction(UIControl *receiver, SEL selector, SEL action, id target, UIEvent *event) {
    if (NSThread.isMainThread) YTKACEPrepareOverlayAction(receiver);
    if (NSThread.isMainThread && Enabled()) {
        if (YTKACEIsPlayerMenuSource(receiver)) YTKACERememberPlayerMenuSource(receiver);
        else if (receiver.window) {
            YTKACEPlayerMenuTap *tap = objc_getAssociatedObject(receiver.window, TapKey);
            if (tap.menu.isViewLoaded && [receiver isDescendantOfView:tap.menu.view])
                tap.uptime = NSProcessInfo.processInfo.systemUptime;
            else objc_setAssociatedObject(receiver.window, TapKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    if (OriginalSendAction) ((void (*)(id, SEL, SEL, id, id))OriginalSendAction)(receiver, selector, action, target, event);
}

static void Present(UIViewController *receiver, SEL selector, UIViewController *controller,
                     BOOL animated, void (^completion)(void)) {
    if (NSThread.isMainThread && Enabled() && !YTKACEIsPlayerPopover(controller) && IsYouTubeMenu(controller)) {
        UIView *source = SourceForPresenter(receiver);
        if (source) {
            CGSize size = controller.preferredContentSize;
            if (size.width <= 0) size.width = 340;
            if (size.height <= 0) size.height = 400;
            YTKACEConfigurePlayerPopover(controller, receiver, source, size);
        }
    }
    if (OriginalPresent) ((void (*)(id, SEL, id, BOOL, id))OriginalPresent)(receiver, selector, controller, animated, completion);
}

void YTKACEInstallPlayerMenuPresentation(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        YTKACEInstallInstanceHook(@"UIControl", @"sendAction:to:forEvent:", (IMP)SendAction, &OriginalSendAction);
        YTKACEInstallInstanceHook(@"UIViewController", @"presentViewController:animated:completion:", (IMP)Present, &OriginalPresent);
    });
}
