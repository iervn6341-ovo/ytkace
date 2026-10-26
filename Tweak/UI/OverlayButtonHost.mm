#import "OverlayButtonHost.h"
#import "SystemMenu.h"
#import "PlayerMenuPresentation.h"
#import "../YTKACE.h"
#import "../Runtime/Hooking.h"
#import "../Runtime/Preferences.h"
#import "../Runtime/Localization.h"
#include "OverlayLayoutPolicy.hpp"

#import <math.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/log.h>

static IMP OriginalControlsOverlayLayout;
static const void *YTKACEButtonRegistryKey = &YTKACEButtonRegistryKey;
static const void *YTKACEButtonOrderKey = &YTKACEButtonOrderKey;
static const void *YTKACESecondRowKey = &YTKACESecondRowKey;
static const void *YTKACEMoreButtonKey = &YTKACEMoreButtonKey;
static const void *YTKACENativeGeometryKey = &YTKACENativeGeometryKey;
@interface YTKACEPlayerRow : UIStackView
@property(nonatomic, weak) UIView *controlsOverlay;
@property(nonatomic, weak) UIScrollView *viewport;
@end
@implementation YTKACEPlayerRow
@end
@interface YTKACEPlayerRowViewport : UIScrollView
@end
@implementation YTKACEPlayerRowViewport
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (gesture == self.panGestureRecognizer) {
        CGPoint velocity = [self.panGestureRecognizer velocityInView:self];
        if (fabs(velocity.y) > fabs(velocity.x)) return NO;
    }
    return [super gestureRecognizerShouldBegin:gesture];
}
@end

static YTKACEPlayerRow *YTKACEMakePlayerRow(UIView *overlay, NSString *identifier, BOOL visible) {
    YTKACEPlayerRow *row = [YTKACEPlayerRow new];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 6;
    row.layoutMargins = UIEdgeInsetsZero;
    row.layoutMarginsRelativeArrangement = YES;
    row.accessibilityIdentifier = identifier;
    row.controlsOverlay = overlay;
    YTKACEPlayerRowViewport *viewport = [YTKACEPlayerRowViewport new];
    viewport.accessibilityIdentifier = [identifier stringByAppendingString:@".Viewport"];
    viewport.directionalLockEnabled = YES;
    viewport.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    viewport.delaysContentTouches = NO;
    viewport.clipsToBounds = YES;
    viewport.showsVerticalScrollIndicator = NO;
    viewport.showsHorizontalScrollIndicator = YES;
    viewport.alwaysBounceVertical = NO;
    viewport.alpha = visible ? 1 : 0;
    viewport.userInteractionEnabled = visible;
    [viewport addSubview:row];
    [overlay addSubview:viewport];
    row.viewport = viewport;
    return row;
}

@interface YTKACENativeGeometry : NSObject
@property(nonatomic) CGRect bounds;
@property(nonatomic) UIEdgeInsets insets;
@property(nonatomic) CGFloat top;
@property(nonatomic, weak) UIView *anchor;
@property(nonatomic, copy) NSArray<NSValue *> *obstacles;
@end
@implementation YTKACENativeGeometry
@end
static const void *YTKACEPrepareActionKey = &YTKACEPrepareActionKey;
static IMP OriginalControlsSetOverlayVisible;
static IMP OriginalControlsSetControlsVisible;
static IMP OriginalVideoSetOverlayVisible;
static IMP OriginalVideoSetControlsVisible;
static IMP OriginalControlsSetHidden;
static const void *YTKACEOverlayStackAssociation = &YTKACEOverlayStackAssociation;
static const void *YTKACEPlayerImageAssociation = &YTKACEPlayerImageAssociation;
static const void *YTKACEOverflowSignatureAssociation = &YTKACEOverflowSignatureAssociation;
static const void *YTKACEPlayerActionAssociation = &YTKACEPlayerActionAssociation;
static NSString *const YTKACEOverflowIdentifier = @"YTKACE More Player Controls";
static NSMutableArray<NSDictionary *> *YTKACEOverlayConfigurators;
static void YTKACEConfigureOverlayActions(UIView *host);
static const void *YTKACELayoutInProgress = &YTKACELayoutInProgress;
static const void *YTKACELayoutState = &YTKACELayoutState;
static const void *YTKACEGestureObservers = &YTKACEGestureObservers;
static const void *YTKACETransitionCompletion = &YTKACETransitionCompletion;

@interface YTKACEPlayerGestureObserver : NSObject
@property(nonatomic, weak) UIView *overlay;
- (void)changed:(UIGestureRecognizer *)gesture;
@end
@implementation YTKACEPlayerGestureObserver
- (void)changed:(UIGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled ||
        gesture.state == UIGestureRecognizerStateFailed) [self.overlay setNeedsLayout];
}
@end

static void YTKACEObservePanEnd(UIGestureRecognizer *gesture, UIView *overlay) {
    NSMapTable *observers = objc_getAssociatedObject(gesture, YTKACEGestureObservers);
    if (!observers) {
        observers = [NSMapTable weakToStrongObjectsMapTable];
        objc_setAssociatedObject(gesture, YTKACEGestureObservers, observers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if ([observers objectForKey:overlay]) return;
    YTKACEPlayerGestureObserver *observer = [YTKACEPlayerGestureObserver new];
    observer.overlay = overlay;
    [observers setObject:observer forKey:overlay];
    // Observe completion; never replace YouTube's delegate or gesture policy.
    [gesture addTarget:observer action:@selector(changed:)];
}

void YTKACEPrepareOverlayAction(UIView *source) {
    dispatch_block_t prepare = objc_getAssociatedObject(source, YTKACEPrepareActionKey);
    if (prepare) prepare();
}

static void YTKACEFindSettingsControlInView(UIView *view,
                                            UIView *excluded,
                                            UIView *coordinateView,
                                            UIView **best,
                                            CGFloat *bestScore) {
    if (view == excluded || [view isDescendantOfView:excluded] ||
        view.hidden || view.alpha < 0.05) {
        return;
    }
    NSString *hint = [[NSString stringWithFormat:@"%@ %@ %@",
        view.accessibilityIdentifier ?: @"", view.accessibilityLabel ?: @"",
        NSStringFromClass(view.class)] lowercaseString];
    if (([view isKindOfClass:UIControl.class] ||
         [view isKindOfClass:UIImageView.class]) &&
        ([hint containsString:@"settings"] || [hint containsString:@"gear"] ||
         [hint containsString:@"設定"] || [hint containsString:@"设置"]) &&
        !CGRectIsEmpty(view.bounds)) {
        CGRect frame = [view convertRect:view.bounds toView:coordinateView];
        CGFloat width = CGRectGetWidth(coordinateView.bounds);
        CGFloat height = CGRectGetHeight(coordinateView.bounds);
        CGFloat centerX = CGRectGetMidX(frame);
        CGFloat centerY = CGRectGetMidY(frame);
        if (isfinite(centerX) && isfinite(centerY) &&
            centerX > width * 0.55 && centerY < height * 0.35 &&
            CGRectIntersectsRect(frame, coordinateView.bounds)) {
            CGFloat score = centerX - centerY * 0.2;
            if (*best == nil || score > *bestScore) {
                *best = view;
                *bestScore = score;
            }
        }
    }
    for (UIView *subview in view.subviews) {
        YTKACEFindSettingsControlInView(subview, excluded, coordinateView,
                                        best, bestScore);
    }
}

static UIView *YTKACEFindSettingsControl(UIView *overlay, UIView *excluded) {
    UIView *best = nil;
    CGFloat bestScore = -CGFLOAT_MAX;
    YTKACEFindSettingsControlInView(overlay, excluded, overlay,
                                    &best, &bestScore);
    return best;
}

static NSString *YTKACEOverlayDeferralReason(UIView *overlay) {
    CGRect bounds = overlay.bounds;
    if (!YTPCValid({bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height})) return @"invalid-bounds";
    UIEdgeInsets insets = overlay.safeAreaInsets;
    if (!isfinite(insets.top) || !isfinite(insets.left) || !isfinite(insets.bottom) || !isfinite(insets.right)) return @"invalid-safe-area";
    CGRect safe = UIEdgeInsetsInsetRect(bounds, insets);
    if (!YTPCValid({safe.origin.x, safe.origin.y, safe.size.width, safe.size.height})) return @"invalid-safe-area";
    for (UIView *node = overlay; node; node = node.superview) {
        CGAffineTransform t = node.transform;
        double determinant = t.a * t.d - t.b * t.c;
        if (!isfinite(t.a) || !isfinite(t.b) || !isfinite(t.c) || !isfinite(t.d) ||
            !isfinite(t.tx) || !isfinite(t.ty) || !isfinite(determinant) || fabs(determinant) < 0.00001)
            return @"noninvertible-transform";
        for (UIGestureRecognizer *gesture in node.gestureRecognizers) {
            if ([gesture isKindOfClass:UIPanGestureRecognizer.class]) YTKACEObservePanEnd(gesture, overlay);
            if ([gesture isKindOfClass:UIPanGestureRecognizer.class] &&
                (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged))
                return @"interactive-pan";
        }
        if ([node.nextResponder isKindOfClass:UIViewController.class]) {
            UIViewController *controller = (id)node.nextResponder;
            id<UIViewControllerTransitionCoordinator> coordinator = controller.transitionCoordinator;
            if (coordinator && objc_getAssociatedObject(overlay, YTKACETransitionCompletion) != coordinator) {
                __weak UIView *weak = overlay;
                objc_setAssociatedObject(overlay, YTKACETransitionCompletion, coordinator, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                BOOL accepted = [coordinator animateAlongsideTransition:nil completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
                    UIView *host = weak;
                    if (host) {
                        objc_setAssociatedObject(host, YTKACETransitionCompletion, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        [host setNeedsLayout];
                    }
                }];
                if (!accepted) objc_setAssociatedObject(overlay, YTKACETransitionCompletion, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (controller.isBeingDismissed || controller.isBeingPresented || coordinator)
                return @"controller-transition";
        }
    }
    if (overlay.window) {
        CGRect frame = [overlay convertRect:bounds toView:overlay.window];
        if (!YTPCValid({frame.origin.x, frame.origin.y, frame.size.width, frame.size.height})) return @"invalid-window-frame";
    }
    return nil;
}

static void YTKACEReportLayoutState(UIView *overlay, NSString *state) {
    NSString *last = objc_getAssociatedObject(overlay, YTKACELayoutState);
    if ([last isEqual:state]) return;
    objc_setAssociatedObject(overlay, YTKACELayoutState, state, OBJC_ASSOCIATION_COPY_NONATOMIC);
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerControls] renderer=local-v3 state=%{public}@ bounds=%{public}@", state, NSStringFromCGRect(overlay.bounds));
}

static BOOL YTKACEKeepControlsVisible(UIView *overlay) {
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.AlwaysShowControls") ||
        !overlay.window || YTKACEOverlayDeferralReason(overlay)) return NO;
    for (UIView *ancestor = overlay; ancestor; ancestor = ancestor.superview)
        if (ancestor.hidden) return NO;
    CGRect frame = [overlay convertRect:overlay.bounds toView:overlay.window];
    return YTPCValid({frame.origin.x, frame.origin.y, frame.size.width, frame.size.height}) &&
        CGRectIntersectsRect(frame, overlay.window.bounds);
}

static void YTKACESetHostedControlsHidden(UIView *view, BOOL hidden) {
    if ([view isKindOfClass:YTKACEPlayerRowViewport.class]) {
        BOOL visible = !hidden;
        if (view.userInteractionEnabled == visible && fabs(view.alpha - (visible ? 1.0 : 0.0)) < 0.001) return;
        view.userInteractionEnabled = visible;
        if (visible) {
            [view.superview setNeedsLayout];
        }
        NSTimeInterval duration = [UIView inheritedAnimationDuration];
        if (duration <= 0 || duration > 1) {
            [UIView performWithoutAnimation:^{ view.alpha = visible ? 1 : 0; }];
            return;
        }
        [UIView animateWithDuration:duration
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionCurveEaseInOut |
                                    UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            view.alpha = visible ? 1.0 : 0.0;
        } completion:nil];
        return;
    }
    for (UIView *subview in view.subviews) {
        YTKACESetHostedControlsHidden(subview, hidden);
    }
}

static void YTKACEUpdateHostedVisibility(UIView *receiver, BOOL visible) {
    YTKACESetHostedControlsHidden(receiver, !visible);
}

static void YTKACEControlsSetOverlayVisible(UIView *receiver, SEL selector, BOOL visible) {
    visible = visible || YTKACEKeepControlsVisible(receiver);
    if (OriginalControlsSetOverlayVisible != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalControlsSetOverlayVisible)(receiver, selector, visible);
    }
    YTKACEUpdateHostedVisibility(receiver, visible);
}

static void YTKACEControlsSetControlsVisible(UIView *receiver, SEL selector, BOOL visible) {
    visible = visible || YTKACEKeepControlsVisible(receiver);
    if (OriginalControlsSetControlsVisible != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalControlsSetControlsVisible)(receiver, selector, visible);
    }
    YTKACEUpdateHostedVisibility(receiver, visible);
}

static void YTKACEVideoSetOverlayVisible(UIView *receiver, SEL selector, BOOL visible) {
    visible = visible || YTKACEKeepControlsVisible(receiver);
    if (OriginalVideoSetOverlayVisible != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalVideoSetOverlayVisible)(receiver, selector, visible);
    }
    YTKACEUpdateHostedVisibility(receiver, visible);
}

static void YTKACEVideoSetControlsVisible(UIView *receiver, SEL selector, BOOL visible) {
    visible = visible || YTKACEKeepControlsVisible(receiver);
    if (OriginalVideoSetControlsVisible != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalVideoSetControlsVisible)(receiver, selector, visible);
    }
    YTKACEUpdateHostedVisibility(receiver, visible);
}

static void YTKACEControlsSetHidden(UIView *receiver, SEL selector, BOOL hidden) {
    // Structural hides select the active overlay/layout; they are not auto-fade.
    if (OriginalControlsSetHidden != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalControlsSetHidden)(receiver, selector, hidden);
    }
    YTKACEUpdateHostedVisibility(receiver, !hidden);
}

static UIStackView *YTKACEStackForOverlay(UIView *overlay) {
    static NSHashTable<UIView *> *overlays;
    static dispatch_once_t observerToken;
    dispatch_once(&observerToken, ^{
        overlays = [NSHashTable weakObjectsHashTable];
        [NSNotificationCenter.defaultCenter addObserverForName:YTKACEPreferencesDidChangeNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                // UIKit coalesces these requests; never force synchronous layout from settings.
                for (UIView *view in overlays.allObjects) [view setNeedsLayout];
            }];
    });
    [overlays addObject:overlay];
    UIStackView *stack = objc_getAssociatedObject(overlay, YTKACEOverlayStackAssociation);
    if (stack != nil) {
        return stack;
    }

    SEL visibility = NSSelectorFromString(@"isOverlayVisible");
    BOOL visible = ![overlay respondsToSelector:visibility] || ((BOOL (*)(id, SEL))objc_msgSend)(overlay,visibility);
    stack = YTKACEMakePlayerRow(overlay,@"YTKACEOverlayControls",visible);
    objc_setAssociatedObject(overlay,
                             YTKACEOverlayStackAssociation,
                             stack,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return stack;
}

static UIImage *YTKACEPlayerGlyph(UIImage *image) {
    if (image == nil || image.size.width <= 0 || image.size.height <= 0) return image;
    if (MAX(image.size.width, image.size.height) <= 24.0) return image;
    UIImage *cached = objc_getAssociatedObject(image, YTKACEPlayerImageAssociation);
    if (cached != nil) return cached;
    CGFloat scale = 24.0 / MAX(image.size.width, image.size.height);
    CGSize size = CGSizeMake(image.size.width * scale, image.size.height * scale);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    cached = [[renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        [image drawInRect:(CGRect){CGPointZero, size}];
    }] imageWithRenderingMode:image.renderingMode];
    objc_setAssociatedObject(image, YTKACEPlayerImageAssociation,
                             cached, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return cached;
}

@interface YTKACEPlayerControlButton : UIButton
@property(nonatomic) BOOL featureHidden;
@property(nonatomic) BOOL layoutHidden;
@end
@implementation YTKACEPlayerControlButton
- (CGSize)intrinsicContentSize { return CGSizeMake(44, 44); }
- (CGSize)sizeThatFits:(CGSize)size { (void)size; return CGSizeMake(44, 44); }
- (void)setHidden:(BOOL)hidden {
    _featureHidden = hidden;
    BOOL effective = hidden || _layoutHidden;
    if (super.hidden != effective) [super setHidden:effective];
}
- (void)setLayoutHidden:(BOOL)hidden {
    if (_layoutHidden == hidden) return;
    _layoutHidden = hidden;
    // Dispatch through the observable hidden setter so UIStackView updates its
    // hiding constraints when an item enters/leaves the overflow menu.
    [self setHidden:_featureHidden];
}
- (CGRect)imageRectForContentRect:(CGRect)contentRect {
    if (!self.currentImage) return CGRectZero;
    CGFloat extent = MIN(24.0, MIN(CGRectGetWidth(contentRect), CGRectGetHeight(contentRect)));
    return CGRectMake(CGRectGetMidX(contentRect) - extent / 2, CGRectGetMidY(contentRect) - extent / 2, extent, extent);
}
- (CGRect)titleRectForContentRect:(CGRect)contentRect { return CGRectInset(contentRect, 2, 0); }
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.imageView.alpha = highlighted ? 0.6 : 1.0;
    self.titleLabel.alpha = highlighted ? 0.6 : 1.0;
}
@end

static UIButton *YTKACENativePlayerButton(UIView *overlay, NSString *identifier,
                                         NSString *symbolName) {
    (void)overlay;
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration
        configurationWithPointSize:24.0 weight:UIImageSymbolWeightRegular];
    UIImage *image = YTKACEPlayerGlyph([UIImage systemImageNamed:symbolName withConfiguration:configuration]);
    // Private YT factories apply additional internal padding and can shrink a
    // 24pt image to ~10pt. Keep a public UIKit button's glyph and hit area separate.
    UIButton *button = [YTKACEPlayerControlButton buttonWithType:UIButtonTypeCustom];
    button.accessibilityIdentifier = identifier;
    YTKACERegisterTweakPlayerMenuSource(button);
    button.accessibilityLabel = identifier;
    button.tintColor = UIColor.whiteColor;
    [button setImage:image forState:UIControlStateNormal];
    [button setPreferredSymbolConfiguration:configuration forImageInState:UIControlStateNormal];
    button.imageView.contentMode = UIViewContentModeScaleAspectFit;
    button.clipsToBounds = YES;
    button.frame = CGRectMake(0, 0, 44, 44);
    button.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *width = [button.widthAnchor constraintEqualToConstant:44.0];
    // UIStackView installs a required zero-width constraint for hidden items.
    width.priority = UILayoutPriorityRequired - 1;
    width.active = YES;
    [button.heightAnchor constraintEqualToConstant:44.0].active = YES;
    return button;
}

UIButton *YTKACEOverlayButton(UIStackView *stack,
                              NSString *identifier,
                              NSString *symbolName,
                              id target,
                              SEL action) {
    NSMutableDictionary *registry = objc_getAssociatedObject(stack, YTKACEButtonRegistryKey);
    if (!registry) {
        registry = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(stack, YTKACEButtonRegistryKey, registry, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (registry[identifier]) return registry[identifier];
    for (UIView *view in stack.arrangedSubviews) {
        if ([view.accessibilityIdentifier isEqualToString:identifier] &&
            [view isKindOfClass:UIButton.class]) {
            return (UIButton *)view;
        }
    }

    UIView *owner = [stack isKindOfClass:YTKACEPlayerRow.class]
        ? (((YTKACEPlayerRow *)stack).controlsOverlay ?: stack.superview) : stack.superview;
    UIButton *button = YTKACENativePlayerButton(owner, identifier, symbolName);
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    __weak id weakTarget = target;
    __weak UIView *weakHost = owner;
    dispatch_block_t prepare = ^{ YTKACEConfigureOverlayActions(weakHost); };
    objc_setAssociatedObject(button, YTKACEPrepareActionKey, prepare, OBJC_ASSOCIATION_COPY_NONATOMIC);
    void (^invoke)(UIButton *) = ^(UIButton *sender) {
        prepare();
        id strongTarget = weakTarget;
        SEL bind = NSSelectorFromString([identifier isEqualToString:@"YTKACE Speed"] ? @"setValueButton:" : @"setButton:");
        if ([strongTarget respondsToSelector:bind]) ((void (*)(id, SEL, id))objc_msgSend)(strongTarget, bind, sender);
        if (strongTarget != nil) [sender sendAction:action to:strongTarget forEvent:nil];
    };
    objc_setAssociatedObject(button, YTKACEPlayerActionAssociation,
                             invoke, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [stack addArrangedSubview:button];
    registry[identifier] = button;
    NSMutableArray *order = objc_getAssociatedObject(stack, YTKACEButtonOrderKey);
    if (!order) {
        order = [NSMutableArray array];
        objc_setAssociatedObject(stack, YTKACEButtonOrderKey, order, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [order addObject:identifier];
    return button;
}

static void YTKACEConfigureOverlayActions(UIView *host) {
    if (!host) return;
    UIStackView *stack = YTKACEStackForOverlay(host);
    NSArray *entries = nil;
    @synchronized (YTKACEOverlayConfigurators) { entries = [YTKACEOverlayConfigurators copy]; }
    for (NSDictionary *entry in entries) {
        // Action preparation only rebinds feature coordinators to this overlay.
        // Walking/styling the native view tree on every action adds transition work.
        if ([entry[@"identifier"] isEqual:@"visibility"]) continue;
        YTKACEOverlayConfigurator configure = entry[@"block"];
        configure(host, stack);
    }
}

static void YTKACECollectNativeControls(UIView *view, UIView *overlay,
                                        UIStackView *stack, std::vector<YTPCFrame>& obstacles,
                                        NSUInteger depth = 0) {
    if (view == stack || [view.accessibilityIdentifier hasPrefix:@"YTKACEOverlayControls"] || view.hidden || view.alpha < 0.05 || depth > 12 || obstacles.size() > 128) return;
    NSString *name = NSStringFromClass(view.class);
    if ([view isKindOfClass:UIControl.class] || view.gestureRecognizers.count ||
        [name containsString:@"TransportControls"] || [name containsString:@"PlaybackButton"] ||
        [name containsString:@"PlayPause"]) {
        CGRect frame = [view convertRect:view.bounds toView:overlay];
        // Ignore full-player tap-catcher buttons, not actual transport controls.
        if (CGRectGetWidth(frame) <= 160 && CGRectGetHeight(frame) <= 160)
            obstacles.push_back({frame.origin.x, frame.origin.y, frame.size.width, frame.size.height});
    }
    for (UIView *child in view.subviews) YTKACECollectNativeControls(child, overlay, stack, obstacles, depth + 1);
}

static UIStackView *YTKACESecondRow(UIView *overlay, UIStackView *first) {
    UIStackView *row = objc_getAssociatedObject(overlay, YTKACESecondRowKey);
    if (row) return row;
    row = YTKACEMakePlayerRow(overlay,@"YTKACEOverlayControls.SecondRow",((YTKACEPlayerRow *)first).viewport.alpha > 0.05);
    objc_setAssociatedObject(overlay, YTKACESecondRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return row;
}

static CGFloat YTKACENativeOpacity(UIView *view, UIView *overlay) {
    if (!view) return 1;
    CGFloat alpha = 1;
    for (UIView *node = view; node; node = node.superview) {
        if (node.hidden) return 0;
        alpha *= node.alpha;
        if (node == overlay) break;
    }
    return alpha;
}

static BOOL YTKACENativeControlGeometry(UIView *overlay, UIStackView *stack,
                                       CGFloat *top, std::vector<YTPCFrame>& obstacles) {
    YTKACENativeGeometry *saved = objc_getAssociatedObject(overlay, YTKACENativeGeometryKey);
    BOOL sameBounds = saved && CGRectEqualToRect(saved.bounds, overlay.bounds) && UIEdgeInsetsEqualToEdgeInsets(saved.insets, overlay.safeAreaInsets);
    UIView *gear = nil;
    for (NSString *name in @[@"settingsButton",@"overflowButton"]) {
        id candidate = nil;
        SEL accessor = NSSelectorFromString(name);
        NSMethodSignature *signature = [overlay methodSignatureForSelector:accessor];
        if (signature.numberOfArguments == 2 && signature.methodReturnType[0] == '@')
            candidate = ((id (*)(id,SEL))objc_msgSend)(overlay,accessor);
        if (!candidate) for (NSString *key in @[name,[@"_" stringByAppendingString:name]]) {
            Ivar ivar = class_getInstanceVariable([overlay class],key.UTF8String);
            if (ivar && ivar_getTypeEncoding(ivar)[0] == '@') { candidate = object_getIvar(overlay,ivar); if (candidate) break; }
        }
        if ([candidate isKindOfClass:UIView.class] && [candidate isDescendantOfView:overlay]) { gear = candidate; break; }
    }
    gear = gear ?: YTKACEFindSettingsControl(overlay, stack) ?: saved.anchor;
    if (gear) YTKACERegisterNativeGearMenuSource(gear);
    SEL visibility = NSSelectorFromString(@"isOverlayVisible");
    BOOL faded = ([overlay respondsToSelector:visibility] && !((BOOL (*)(id, SEL))objc_msgSend)(overlay, visibility)) ||
        YTKACENativeOpacity(gear ?: overlay, overlay) < 0.98;
    if (faded) {
        // Fading is not removal. Keep the last visible native reservations and
        // anchor; never slide custom controls into their temporarily empty slots.
        if (!sameBounds) return NO;
        *top = saved.top;
        for (NSValue *value in saved.obstacles) {
            CGRect r = value.CGRectValue;
            obstacles.push_back({r.origin.x,r.origin.y,r.size.width,r.size.height});
        }
        return YES;
    }
    if (gear) {
        CGRect r = [gear convertRect:gear.bounds toView:overlay];
        if (YTPCValid({r.origin.x,r.origin.y,r.size.width,r.size.height})) *top = MAX(*top,CGRectGetMidY(r) - 22);
    }
    YTKACECollectNativeControls(overlay, overlay, stack, obstacles);
    YTKACENativeGeometry *snapshot = [YTKACENativeGeometry new];
    snapshot.bounds = overlay.bounds; snapshot.insets = overlay.safeAreaInsets;
    snapshot.top = *top; snapshot.anchor = gear;
    NSMutableArray *frames = [NSMutableArray array];
    for (auto r : obstacles) if (YTPCValid(r)) [frames addObject:[NSValue valueWithCGRect:CGRectMake(r.x,r.y,r.width,r.height)]];
    snapshot.obstacles = frames;
    objc_setAssociatedObject(overlay, YTKACENativeGeometryKey, snapshot, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

static void YTKACEPlaceInRow(UIButton *button, UIStackView *row, NSUInteger index) {
    if (button.superview != row) {
        if ([button.superview isKindOfClass:UIStackView.class]) [(UIStackView *)button.superview removeArrangedSubview:button];
        [button removeFromSuperview];
        [row insertArrangedSubview:button atIndex:MIN(index,row.arrangedSubviews.count)];
    } else if ([row.arrangedSubviews indexOfObjectIdenticalTo:button] != index) {
        [row removeArrangedSubview:button];
        [row insertArrangedSubview:button atIndex:MIN(index,row.arrangedSubviews.count)];
    }
}

static void YTKACELayoutPlayerButtons(UIView *overlay, UIStackView *stack) {
    NSMutableArray<UIButton *> *wanted = [NSMutableArray array];
    UIButton *more = objc_getAssociatedObject(stack, YTKACEMoreButtonKey);
    NSDictionary *registry = objc_getAssociatedObject(stack, YTKACEButtonRegistryKey);
    NSArray *order = objc_getAssociatedObject(stack, YTKACEButtonOrderKey);
    for (NSString *identifier in order) {
        UIView *view = registry[identifier];
        if (![view isKindOfClass:UIButton.class]) continue;
        UIButton *button = (UIButton *)view;
        if ([button.accessibilityIdentifier isEqualToString:YTKACEOverflowIdentifier]) {
            more = button;
            continue;
        }
        for (NSNumber *state in @[@(UIControlStateNormal), @(UIControlStateSelected), @(UIControlStateHighlighted)]) {
            UIImage *image = [button imageForState:state.unsignedIntegerValue];
            UIImage *glyph = YTKACEPlayerGlyph(image);
            if (image != glyph) [button setImage:glyph forState:state.unsignedIntegerValue];
        }
        BOOL featureHidden = [button isKindOfClass:YTKACEPlayerControlButton.class]
            ? ((YTKACEPlayerControlButton *)button).featureHidden : button.hidden;
        if (!featureHidden) [wanted addObject:button];
    }
    for (UIButton *button in wanted.copy) if ([button.accessibilityIdentifier isEqual:@"YTKACE Download"]) {
        [wanted removeObjectIdenticalTo:button]; [wanted insertObject:button atIndex:0]; break;
    }
    CGRect safe = UIEdgeInsetsInsetRect(overlay.bounds, overlay.safeAreaInsets);
    CGFloat left = CGRectGetMinX(safe) + 8.0;
    CGFloat right = CGRectGetMaxX(safe) - 8.0;
    CGFloat top = CGRectGetMinY(safe) + 4.0;
    std::vector<YTPCFrame> obstacles;
    UIStackView *second = YTKACESecondRow(overlay, stack);
    if (!YTKACENativeControlGeometry(overlay, stack, &top, obstacles)) {
        ((YTKACEPlayerRow *)stack).viewport.hidden = YES; ((YTKACEPlayerRow *)second).viewport.hidden = YES;
        return;
    }
    auto plan = ytkace::planPlayerToolbar(left, right, top, CGRectGetMaxY(safe) - 52, wanted.count, obstacles);
    BOOL expanded = [NSUserDefaults.standardUserDefaults integerForKey:@"YTKACE.Preference.Overlay.ButtonLayout"] == 0;
    if (expanded && plan.overflowCount) {
        if (YTPCValid(plan.second)) {
            plan.secondCount = wanted.count - plan.firstCount;
        } else if (YTPCValid(plan.first)) {
            plan.firstCount = wanted.count;
        }
        plan.overflowCount = 0;
    }
    UIScrollView *firstViewport = ((YTKACEPlayerRow *)stack).viewport;
    UIScrollView *secondViewport = ((YTKACEPlayerRow *)second).viewport;
    firstViewport.hidden = !YTPCValid(plan.first);
    secondViewport.hidden = !YTPCValid(plan.second);
    const NSUInteger shown = plan.firstCount + plan.secondCount;
    for (NSUInteger index = 0; index < wanted.count; ++index) {
        UIButton *button = wanted[index];
        ((YTKACEPlayerControlButton *)button).layoutHidden = index >= shown;
        if (index < plan.firstCount) YTKACEPlaceInRow(button,stack,index);
        else if (index < shown) YTKACEPlaceInRow(button,second,index - plan.firstCount);
    }
    if (more) ((YTKACEPlayerControlButton *)more).layoutHidden = plan.overflowCount == 0;
    if (plan.overflowCount != 0) {
        if (more == nil) {
            more = YTKACENativePlayerButton(overlay, YTKACEOverflowIdentifier, @"ellipsis");
            more.accessibilityLabel = YTKACELocalized(@"More player controls");
            more.showsMenuAsPrimaryAction = YES;
            objc_setAssociatedObject(stack, YTKACEMoreButtonKey, more, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIStackView *row = plan.overflowOnSecond ? second : stack;
        YTKACEPlaceInRow(more,row,plan.overflowOnSecond ? plan.secondCount : plan.firstCount);
        NSMutableArray<UIAction *> *actions = [NSMutableArray array];
        NSMutableArray *signature = [NSMutableArray array];
        __weak UIButton *weakMore = more;
        for (NSUInteger index = shown; index < wanted.count; ++index) {
            UIButton *button = wanted[index];
            NSString *label = button.accessibilityLabel ?: button.accessibilityIdentifier;
            if ([label hasPrefix:@"YTKACE "]) label = [label substringFromIndex:7];
            NSString *title = YTKACELocalized(label ?: @"");
            if (button.currentTitle.length != 0) title = [title stringByAppendingFormat:@" · %@", button.currentTitle];
            [signature addObject:@[button.accessibilityIdentifier ?: @"", title, @(button.enabled), @(button.selected)]];
            __weak UIButton *weakButton = button;
            UIAction *action = [UIAction actionWithTitle:title image:button.currentImage identifier:nil handler:^(__unused UIAction *item) {
                UIButton *source = weakMore;
                UIButton *original = weakButton;
                if (source == nil || original == nil || !original.enabled) return;
                // Preserve the visible overflow button as the native submenu anchor.
                YTKACERememberPlayerMenuSource(source);
                void (^invoke)(UIButton *) = objc_getAssociatedObject(original, YTKACEPlayerActionAssociation);
                if (invoke != nil) invoke(source);
            }];
            action.attributes = button.enabled ? 0 : UIMenuElementAttributesDisabled;
            action.state = button.selected ? UIMenuElementStateOn : UIMenuElementStateOff;
            [actions addObject:action];
        }
        if (![signature isEqual:objc_getAssociatedObject(more, YTKACEOverflowSignatureAssociation)]) {
            more.menu = [UIMenu menuWithTitle:@"" children:actions];
            objc_setAssociatedObject(more, YTKACEOverflowSignatureAssociation,
                                     [signature copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        ((YTKACEPlayerControlButton *)more).layoutHidden = NO;
    }
    auto placeRow = [&](UIStackView *row, UIScrollView *viewport, YTPCFrame frame, NSUInteger count) {
        if (!YTPCValid(frame)) return;
        CGRect outer = CGRectMake(frame.x,frame.y,frame.width,44);
        if (!CGRectEqualToRect(viewport.frame,outer)) viewport.frame = outer;
        CGFloat width = count ? count * 44 + (count - 1) * 6 : 0;
        CGRect inner = CGRectMake(0,0,width,44);
        if (!CGRectEqualToRect(row.frame,inner)) row.frame = inner;
        CGSize size = CGSizeMake(width,44);
        if (!CGSizeEqualToSize(viewport.contentSize,size)) viewport.contentSize = size;
        viewport.scrollEnabled = expanded && width > frame.width + 1;
        if (!viewport.scrollEnabled && !CGPointEqualToPoint(viewport.contentOffset,CGPointZero)) viewport.contentOffset = CGPointZero;
    };
    placeRow(stack,firstViewport,plan.first,plan.firstCount + (plan.overflowCount && !plan.overflowOnSecond));
    placeRow(second,secondViewport,plan.second,plan.secondCount + (plan.overflowCount && plan.overflowOnSecond));
    NSString *diagnostic = [NSString stringWithFormat:@"mode=%@ active=%lu first=%lu second=%lu overflow=%lu buttons=%@",
        expanded ? @"expanded" : @"more",(unsigned long)wanted.count,(unsigned long)plan.firstCount,
        (unsigned long)plan.secondCount,(unsigned long)plan.overflowCount,
        [wanted valueForKey:@"accessibilityIdentifier"]];
    static const void *snapshotKey = &snapshotKey;
    if (![diagnostic isEqual:objc_getAssociatedObject(overlay,snapshotKey)]) {
        objc_setAssociatedObject(overlay,snapshotKey,diagnostic,OBJC_ASSOCIATION_COPY_NONATOMIC);
        os_log(OS_LOG_DEFAULT,"[YTKACE PlayerControls] %{public}@",diagnostic);
    }
}

static void YTKACEControlsOverlayLayout(UIView *receiver, SEL selector) {
    // UIKit can synchronously revisit layout while native controls are transitioning.
    // Never configure/reparent buttons recursively on the same overlay.
    if ([objc_getAssociatedObject(receiver, YTKACELayoutInProgress) boolValue]) return;
    objc_setAssociatedObject(receiver, YTKACELayoutInProgress, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
    @try {
        if (OriginalControlsOverlayLayout) ((void (*)(id, SEL))OriginalControlsOverlayLayout)(receiver, selector);
        NSString *deferred = YTKACEOverlayDeferralReason(receiver);
        UIStackView *stack = objc_getAssociatedObject(receiver, YTKACEOverlayStackAssociation);
        if (deferred) {
            if ([deferred hasPrefix:@"invalid"] || [deferred isEqual:@"noninvertible-transform"]) {
                ((YTKACEPlayerRow *)stack).viewport.hidden = YES;
                ((YTKACEPlayerRow *)objc_getAssociatedObject(receiver,YTKACESecondRowKey)).viewport.hidden = YES;
            }
            YTKACEReportLayoutState(receiver, deferred);
            return;
        }
        stack = YTKACEStackForOverlay(receiver);
        YTKACEConfigureOverlayActions(receiver);
        NSArray *entries = nil;
        @synchronized (YTKACEOverlayConfigurators) { entries = [YTKACEOverlayConfigurators copy]; }
        for (NSDictionary *entry in entries) {
            if (![entry[@"identifier"] isEqual:@"visibility"]) continue;
            YTKACEOverlayConfigurator configure = entry[@"block"];
            configure(receiver, stack);
        }
        YTKACELayoutPlayerButtons(receiver, stack);
        UIView *second = ((YTKACEPlayerRow *)objc_getAssociatedObject(receiver,YTKACESecondRowKey)).viewport;
        UIView *first = ((YTKACEPlayerRow *)stack).viewport;
        if (second) {
            if (receiver.subviews.lastObject != second) [receiver bringSubviewToFront:second];
            NSUInteger index = [receiver.subviews indexOfObjectIdenticalTo:second];
            if (index > 0 && receiver.subviews[index - 1] != first) [receiver insertSubview:first belowSubview:second];
        }
        YTKACEReportLayoutState(receiver, first.hidden && second.hidden ? @"no-free-slot" : @"local-rows-visible");
    } @finally {
        objc_setAssociatedObject(receiver, YTKACELayoutInProgress, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSTimeInterval duration = NSProcessInfo.processInfo.systemUptime - started;
        static NSTimeInterval lastSlowLog;
        if (duration >= 0.05 && started - lastSlowLog >= 5) {
            lastSlowLog = started;
            os_log(OS_LOG_DEFAULT,"[YTKACE PlayerControls] slow layout %.0fms bounds=%{public}@", duration * 1000, NSStringFromCGRect(receiver.bounds));
        }
    }
}

void YTKACERegisterOverlayConfigurator(NSString *identifier,
                                       YTKACEOverlayConfigurator configurator) {
    if (identifier.length == 0 || configurator == nil) {
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        YTKACEOverlayConfigurators = [NSMutableArray array];
    });

    @synchronized (YTKACEOverlayConfigurators) {
        for (NSDictionary *entry in YTKACEOverlayConfigurators) {
            if ([entry[@"identifier"] isEqualToString:identifier]) {
                return;
            }
        }
        [YTKACEOverlayConfigurators addObject:@{
            @"identifier": identifier,
            @"block": [configurator copy]
        }];
    }

    YTKACEInstallInstanceHook(@"YTMainAppControlsOverlayView",
                              @"layoutSubviews",
                              (IMP)YTKACEControlsOverlayLayout,
                              &OriginalControlsOverlayLayout);
    YTKACEInstallInstanceHook(@"YTMainAppControlsOverlayView",
                              @"setOverlayVisible:",
                              (IMP)YTKACEControlsSetOverlayVisible,
                              &OriginalControlsSetOverlayVisible);
    YTKACEInstallInstanceHook(@"YTMainAppControlsOverlayView",
                              @"setControlsOverlayVisible:",
                              (IMP)YTKACEControlsSetControlsVisible,
                              &OriginalControlsSetControlsVisible);
    YTKACEInstallInstanceHook(@"YTMainAppVideoPlayerOverlayView",
                              @"setOverlayVisible:",
                              (IMP)YTKACEVideoSetOverlayVisible,
                              &OriginalVideoSetOverlayVisible);
    YTKACEInstallInstanceHook(@"YTMainAppVideoPlayerOverlayView",
                              @"setControlsOverlayVisible:",
                              (IMP)YTKACEVideoSetControlsVisible,
                              &OriginalVideoSetControlsVisible);
    YTKACEInstallInstanceHook(@"YTMainAppControlsOverlayView",
                              @"setHidden:",
                              (IMP)YTKACEControlsSetHidden,
                              &OriginalControlsSetHidden);
}

static UIViewController *YTKACESheetPresenter(UIView *sourceView) {
    UIResponder *responder = sourceView;
    for (NSUInteger depth = 0; responder != nil && depth < 20; depth++) {
        SEL eventsSelector = NSSelectorFromString(@"eventsDelegate");
        if ([responder respondsToSelector:eventsSelector]) {
            id events = ((id (*)(id, SEL))objc_msgSend)(responder, eventsSelector);
            if (events != nil) return events;
        }
        if ([responder isKindOfClass:UIViewController.class]) {
            return (UIViewController *)responder;
        }
        responder = responder.nextResponder;
    }
    return nil;
}

id YTKACEMakeSheet(NSString *title, NSString *subtitle) {
    Class sheetClass = NSClassFromString(@"YTDefaultSheetController");
    if (sheetClass == Nil) return nil;
    SEL init = NSSelectorFromString(
        @"initWithSheetStyle:headerTitle:headerSubtitle:shouldDisableLogging:delegate:parentResponder:");
    if ([sheetClass instancesRespondToSelector:init]) {
        return ((id (*)(id, SEL, NSInteger, id, id, BOOL, id, id))objc_msgSend)(
            [sheetClass alloc], init, 2, title, subtitle, NO, nil, nil);
    }
    SEL makeSheet = NSSelectorFromString(@"sheetControllerWithMessage:subMessage:delegate:parentResponder:");
    if (![sheetClass respondsToSelector:makeSheet]) return nil;
    return ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(sheetClass, makeSheet, title, subtitle, nil, nil);
}

BOOL YTKACEShowSheet(id sheet, UIViewController *presenter) {
    SEL present = NSSelectorFromString(@"presentFromViewController:animated:completion:");
    if (sheet == nil || presenter == nil || ![sheet respondsToSelector:present]) return NO;
    ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(sheet, present, presenter, YES, nil);
    return YES;
}

void YTKACEPresentNativeSheet(NSString *title,
                              NSString *subtitle,
                              UIView *sourceView,
                              NSArray<NSDictionary *> *actions) {
    if (YTKACEPresentSystemMenu(YTKACESheetPresenter(sourceView), sourceView, title, subtitle, actions)) return;
    Class actionClass = NSClassFromString(@"YTActionSheetAction");
    SEL makeSimple = NSSelectorFromString(@"actionWithTitle:iconImage:style:handler:");
    SEL makeDetailed = NSSelectorFromString(
        @"actionWithTitle:iconImage:secondaryIconImage:accessibilityIdentifier:handler:");
    SEL makeValued = NSSelectorFromString(
        @"actionWithTitle:currentValue:iconImage:accessibilityIdentifier:handler:");
    SEL makeSelectable = NSSelectorFromString(
        @"actionWithTitle:subtitle:iconImage:visiblySelected:accessibilityLabel:"
        @"accessibilityIdentifier:handler:");
    SEL makeSubtitled = NSSelectorFromString(
        @"actionWithTitle:subtitle:iconImage:accessibilityIdentifier:handler:");
    SEL addAction = NSSelectorFromString(@"addAction:");
    if (actionClass == Nil ||
        ![actionClass respondsToSelector:makeSimple]) {
        return;
    }
    id sheet = YTKACEMakeSheet(title.length != 0 ? title : nil, subtitle.length != 0 ? subtitle : nil);
    if (sheet == nil || ![sheet respondsToSelector:addAction]) return;

    for (NSDictionary *item in actions) {
        dispatch_block_t handler = item[@"handler"];
        UIImage *secondary = item[@"secondary"];
        NSString *value = item[@"value"];
        NSString *subtitle = item[@"subtitle"];
        id action = nil;
        if ([actionClass respondsToSelector:makeSelectable]) {
            action = ((id (*)(id, SEL, id, id, id, BOOL, id, id, id))objc_msgSend)(
                actionClass, makeSelectable, item[@"title"], subtitle,
                item[@"icon"], NO, nil, nil, handler);
        } else if (subtitle.length != 0 &&
                   [actionClass respondsToSelector:makeSubtitled]) {
            action = ((id (*)(id, SEL, id, id, id, id, id))objc_msgSend)(
                actionClass, makeSubtitled, item[@"title"], subtitle,
                item[@"icon"], nil, handler);
        } else if (value.length != 0 && [actionClass respondsToSelector:makeValued]) {
            action = ((id (*)(id, SEL, id, id, id, id, id))objc_msgSend)(
                actionClass, makeValued, item[@"title"], value, item[@"icon"],
                nil, handler);
            SEL setSecondary = NSSelectorFromString(@"setSecondaryIconImage:");
            if (secondary != nil && [action respondsToSelector:setSecondary]) {
                ((void (*)(id, SEL, id))objc_msgSend)(
                    action, setSecondary, secondary);
            }
        } else if (secondary != nil && [actionClass respondsToSelector:makeDetailed]) {
            action = ((id (*)(id, SEL, id, id, id, id, id))objc_msgSend)(
                actionClass, makeDetailed, item[@"title"], item[@"icon"],
                secondary, nil, handler);
        } else {
            action = ((id (*)(id, SEL, id, id, NSInteger, id))objc_msgSend)(
                actionClass, makeSimple, item[@"title"], item[@"icon"], 0, handler);
        }
        if (action != nil) {
            ((void (*)(id, SEL, id))objc_msgSend)(sheet, addAction, action);
        }
    }

    YTKACEShowSheet(sheet, YTKACESheetPresenter(sourceView));
}
