#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>

static IMP OriginalFrostedLayout;
static IMP OriginalFrostedMoveToWindow;
static const void *YTKACEPlayerGlassAssociation = &YTKACEPlayerGlassAssociation;
static const void *YTKACEGlassLayoutBusy = &YTKACEGlassLayoutBusy;
static const void *YTKACEGlassNativeAlpha = &YTKACEGlassNativeAlpha;
static const void *YTKACEGlassState = &YTKACEGlassState;

static BOOL YTKACEInPlayerControls(UIView *view) {
    NSUInteger depth = 0;
    for (UIView *current = view.superview; current != nil && depth < 10; current = current.superview, depth++) {
        NSString *name = NSStringFromClass(current.class);
        if ([name containsString:@"Overlay"] || [name containsString:@"Player"] ||
            [name containsString:@"Fullscreen"] || [name containsString:@"Watch"]) return YES;
    }
    return NO;
}

static NSArray<UIView *> *YTKACEFrostedLayers(UIView *frosted) {
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    for (NSString *key in @[@"_blurEffectView", @"_overlayView"]) {
        id view = nil;
        @try { view = [frosted valueForKey:key]; } @catch (__unused NSException *exception) {}
        if ([view isKindOfClass:UIView.class]) [views addObject:view];
    }
    return views;
}

static void YTKACEGlassReport(UIView *receiver, NSString *state) {
    if ([state isEqual:objc_getAssociatedObject(receiver, YTKACEGlassState)]) return;
    objc_setAssociatedObject(receiver, YTKACEGlassState, state, OBJC_ASSOCIATION_COPY_NONATOMIC);
    NSLog(@"[YTKACE PlayerGlass] state=%@ bounds=%@", state, NSStringFromCGRect(receiver.bounds));
}

static void YTKACERestoreNativeGlass(UIView *receiver, UIVisualEffectView *glass) {
    if (!glass) return;
    if (glass && !glass.hidden) glass.hidden = YES;
    for (UIView *layer in YTKACEFrostedLayers(receiver)) {
        NSNumber *alpha = objc_getAssociatedObject(layer, YTKACEGlassNativeAlpha);
        if (!alpha) continue;
        if (layer.alpha == 0) layer.alpha = alpha.doubleValue;
        objc_setAssociatedObject(layer, YTKACEGlassNativeAlpha, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static NSString *YTKACEGlassDeferral(UIView *receiver) {
    CGRect r = receiver.bounds;
    if (!isfinite(r.origin.x) || !isfinite(r.origin.y) || !isfinite(r.size.width) || !isfinite(r.size.height) ||
        r.size.width <= 0 || r.size.height <= 0) return @"invalid-geometry";
    // The preference styles buttons. Large native player/backdrop surfaces keep
    // their original material rather than adding live glass over the whole video.
    if (r.size.width > 180 || r.size.height > 120) return @"native-large-surface";
    for (UIView *node = receiver; node; node = node.superview) {
        CGAffineTransform t = node.transform;
        if (!isfinite(t.a) || !isfinite(t.b) || !isfinite(t.c) || !isfinite(t.d) ||
            !isfinite(t.tx) || !isfinite(t.ty) || fabs(t.a * t.d - t.b * t.c) < 0.00001) return @"invalid-transform";
        if (!CGAffineTransformIsIdentity(t)) return @"transformed-control";
        for (UIGestureRecognizer *gesture in node.gestureRecognizers)
            if ([gesture isKindOfClass:UIPanGestureRecognizer.class] &&
                (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged)) return @"interactive-pan";
        if ([node.nextResponder isKindOfClass:UIViewController.class]) {
            UIViewController *controller = (id)node.nextResponder;
            if (controller.transitionCoordinator || controller.isBeingDismissed || controller.isBeingPresented) return @"controller-transition";
        }
    }
    return nil;
}

static BOOL YTKACEHasNativeGlass(UIView *view, UIView *owned, NSUInteger depth) {
    if (!view || view == owned || depth == 0) return NO;
    if ([view isKindOfClass:UIVisualEffectView.class] &&
        [((UIVisualEffectView *)view).effect isKindOfClass:NSClassFromString(@"UIGlassEffect")]) return YES;
    for (UIView *child in view.subviews) if (YTKACEHasNativeGlass(child, owned, depth - 1)) return YES;
    return NO;
}

static void YTKACEApplyFrostedGlass(UIView *receiver) {
    UIVisualEffectView *glass = objc_getAssociatedObject(receiver, YTKACEPlayerGlassAssociation);
    BOOL enabled = YTKACELiquidGlassAvailable() && YTKACEFeatureEnabled(@"YTKACE.Preference.Glass.Player") &&
        !UIAccessibilityIsReduceTransparencyEnabled();
    if (!enabled || !YTKACEInPlayerControls(receiver)) {
        YTKACERestoreNativeGlass(receiver, glass);
        return;
    }
    NSString *deferred = receiver.window ? YTKACEGlassDeferral(receiver) : @"offscreen";
    BOOL nativeGlass = YTKACEHasNativeGlass(receiver, glass, 5);
    for (UIView *node = receiver.superview; node && !nativeGlass; node = node.superview)
        if ([node isKindOfClass:UIVisualEffectView.class] &&
            [((UIVisualEffectView *)node).effect isKindOfClass:NSClassFromString(@"UIGlassEffect")]) nativeGlass = YES;
    if (deferred || nativeGlass) {
        YTKACERestoreNativeGlass(receiver, glass);
        YTKACEGlassReport(receiver, deferred ?: @"native-glass");
        return;
    }
    if (glass == nil) {
        Class effectClass = NSClassFromString(@"UIGlassEffect");
        SEL styleSelector = NSSelectorFromString(@"effectWithStyle:");
        UIVisualEffect *effect = [effectClass respondsToSelector:styleSelector]
            ? ((id (*)(id, SEL, NSInteger))objc_msgSend)(effectClass, styleSelector, 0)
            : nil;
        if (!effect) return;
        glass = [[UIVisualEffectView alloc] initWithEffect:effect];
        glass.userInteractionEnabled = NO;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.clipsToBounds = YES;
        objc_setAssociatedObject(receiver, YTKACEPlayerGlassAssociation, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (glass.superview != receiver) [receiver insertSubview:glass atIndex:0];
    // Use bounds/center and update only actual changes. Reassigning an effect
    // frame on every native layout can continually invalidate its render graph.
    CGRect bounds = (CGRect){CGPointZero, receiver.bounds.size};
    CGPoint center = CGPointMake(CGRectGetMidX(receiver.bounds), CGRectGetMidY(receiver.bounds));
    if (!CGRectEqualToRect(glass.bounds, bounds)) glass.bounds = bounds;
    if (!CGPointEqualToPoint(glass.center, center)) glass.center = center;
    CGFloat radius = receiver.layer.cornerRadius;
    CGFloat capsule = MIN(receiver.bounds.size.width, receiver.bounds.size.height) * 0.5;
    radius = radius > 0 ? MIN(radius, capsule) : capsule;
    if (glass.layer.cornerRadius != radius) glass.layer.cornerRadius = radius;
    if (glass.hidden) glass.hidden = NO;
    for (UIView *layer in YTKACEFrostedLayers(receiver)) {
        if (layer.alpha != 0) {
            objc_setAssociatedObject(layer, YTKACEGlassNativeAlpha, @(layer.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            layer.alpha = 0;
        }
    }
    YTKACEGlassReport(receiver, @"custom-glass");
}

static void YTKACEFrostedLayout(UIView *receiver, SEL selector) {
    UIVisualEffectView *glass = objc_getAssociatedObject(receiver, YTKACEPlayerGlassAssociation);
    if (!glass && !YTKACEInPlayerControls(receiver)) {
        if (OriginalFrostedLayout) ((void (*)(id, SEL))OriginalFrostedLayout)(receiver, selector);
        return;
    }
    if ([objc_getAssociatedObject(receiver, YTKACEGlassLayoutBusy) boolValue]) return;
    objc_setAssociatedObject(receiver, YTKACEGlassLayoutBusy, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        // Release our material before native transition layout, allowing native
        // alpha/geometry updates to take precedence throughout the animation.
        if (glass && YTKACEGlassDeferral(receiver)) YTKACERestoreNativeGlass(receiver, glass);
        if (OriginalFrostedLayout) ((void (*)(id, SEL))OriginalFrostedLayout)(receiver, selector);
        YTKACEApplyFrostedGlass(receiver);
    } @finally {
        objc_setAssociatedObject(receiver, YTKACEGlassLayoutBusy, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void YTKACEFrostedMoveToWindow(UIView *receiver, SEL selector) {
    if (OriginalFrostedMoveToWindow != NULL) ((void (*)(id, SEL))OriginalFrostedMoveToWindow)(receiver, selector);
    if (receiver.window != nil) [receiver setNeedsLayout];
}

__attribute__((constructor)) static void YTKACEInstallPlayerGlass(void) {
    if (!YTKACELiquidGlassAvailable()) return;
    YTKACEInstallInstanceHook(@"YTFrostedGlassView", @"layoutSubviews",
                              (IMP)YTKACEFrostedLayout, &OriginalFrostedLayout);
    YTKACEInstallInstanceHook(@"YTFrostedGlassView", @"didMoveToWindow",
                              (IMP)YTKACEFrostedMoveToWindow, &OriginalFrostedMoveToWindow);
}
