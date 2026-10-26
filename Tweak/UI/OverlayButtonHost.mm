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

static IMP OriginalControlsOverlayLayout;
static const void *YTKACEButtonRegistryKey = &YTKACEButtonRegistryKey;
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
        ([hint containsString:@"settings"] || [hint containsString:@"gear"]) &&
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

static BOOL YTKACEIsTopTrailingControl(UIView *view, UIView *overlay) {
    CGRect frame = [view convertRect:view.bounds toView:overlay];
    CGFloat width = CGRectGetWidth(overlay.bounds);
    CGFloat height = CGRectGetHeight(overlay.bounds);
    CGFloat centerX = CGRectGetMidX(frame);
    CGFloat centerY = CGRectGetMidY(frame);
    return isfinite(centerX) && isfinite(centerY) &&
        centerX > width * 0.55 && centerY < height * 0.35 &&
        CGRectIntersectsRect(frame, overlay.bounds);
}

static UIView *YTKACEOverflowControl(UIView *overlay) {
    SEL selector = NSSelectorFromString(@"overflowButton");
    if (![overlay respondsToSelector:selector]) return nil;
    UIView *button = ((id (*)(id, SEL))objc_msgSend)(overlay, selector);
    if (![button isKindOfClass:UIView.class] || button.hidden ||
        button.alpha < 0.05 || CGRectIsEmpty(button.bounds)) {
        return nil;
    }
    return YTKACEIsTopTrailingControl(button, overlay) ? button : nil;
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
    NSLog(@"[YTKACE PlayerControls] renderer=local-v2 state=%@ bounds=%@", state, NSStringFromCGRect(overlay.bounds));
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
    if ([view.accessibilityIdentifier isEqualToString:@"YTKACEOverlayControls"]) {
        BOOL visible = !hidden;
        if (view.userInteractionEnabled == visible && fabs(view.alpha - (visible ? 1.0 : 0.0)) < 0.001) return;
        view.userInteractionEnabled = visible;
        if (visible) {
            [view.superview setNeedsLayout];
        }
        NSTimeInterval duration = [UIView inheritedAnimationDuration];
        if (duration <= 0.0 || duration > 1.0) duration = 0.20;
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

    stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.distribution = UIStackViewDistributionFill;
    stack.spacing = 6.0;
    stack.layoutMargins = UIEdgeInsetsZero;
    stack.layoutMarginsRelativeArrangement = YES;
    stack.backgroundColor = UIColor.clearColor;
    SEL visibility = NSSelectorFromString(@"isOverlayVisible");
    BOOL visible = ![overlay respondsToSelector:visibility] ||
        ((BOOL (*)(id, SEL))objc_msgSend)(overlay, visibility);
    stack.alpha = visible ? 1.0 : 0.0;
    stack.userInteractionEnabled = visible;
    stack.clipsToBounds = YES;
    stack.translatesAutoresizingMaskIntoConstraints = YES;
    stack.accessibilityIdentifier = @"YTKACEOverlayControls";

    [overlay addSubview:stack];
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

    UIButton *button = YTKACENativePlayerButton(stack.superview, identifier, symbolName);
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    __weak id weakTarget = target;
    __weak UIView *weakHost = stack.superview;
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
    if (view == stack || view.hidden || view.alpha < 0.05 || depth > 12 || obstacles.size() > 128) return;
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

static void YTKACELayoutPlayerButtons(UIView *overlay, UIStackView *stack) {
    NSMutableArray<UIButton *> *wanted = [NSMutableArray array];
    UIButton *more = nil;
    for (UIView *view in stack.arrangedSubviews) {
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
    CGRect safe = UIEdgeInsetsInsetRect(overlay.bounds, overlay.safeAreaInsets);
    CGFloat left = CGRectGetMinX(safe) + 8.0;
    CGFloat right = CGRectGetMaxX(safe) - 8.0;
    CGFloat top = CGRectGetMinY(safe) + 4.0;
    UIView *gear = YTKACEOverflowControl(overlay) ?: YTKACEFindSettingsControl(overlay, stack);
    if (gear != nil) {
        CGRect frame = [gear convertRect:gear.bounds toView:overlay];
        if (YTPCValid({frame.origin.x, frame.origin.y, frame.size.width, frame.size.height}))
            top = MAX(top, CGRectGetMidY(frame) - 22.0);
    }
    std::vector<YTPCFrame> obstacles;
    YTKACECollectNativeControls(overlay, overlay, stack, obstacles);
    auto plan = ytkace::planPlayerControls(left, right, top, CGRectGetMaxY(safe) - 52.0, wanted.count, obstacles);
    stack.hidden = !plan.fits;
    if (!plan.fits) {
        for (UIView *view in stack.arrangedSubviews)
            if ([view isKindOfClass:YTKACEPlayerControlButton.class]) ((YTKACEPlayerControlButton *)view).layoutHidden = YES;
        CGRect empty = CGRectMake(CGRectGetMinX(safe), CGRectGetMinY(safe), 0, 44);
        if (!CGRectEqualToRect(stack.frame, empty)) stack.frame = empty;
        return;
    }
    for (NSUInteger index = 0; index < wanted.count; ++index) {
        UIButton *button = wanted[index];
        if ([button isKindOfClass:YTKACEPlayerControlButton.class])
            ((YTKACEPlayerControlButton *)button).layoutHidden = index >= plan.inlineCount;
        else button.hidden = index >= plan.inlineCount;
    }
    if (more != nil) ((YTKACEPlayerControlButton *)more).layoutHidden = plan.overflowCount == 0;
    if (plan.overflowCount != 0) {
        if (more == nil) {
            more = YTKACENativePlayerButton(overlay, YTKACEOverflowIdentifier, @"ellipsis");
            more.accessibilityLabel = YTKACELocalized(@"More player controls");
            more.showsMenuAsPrimaryAction = YES;
            [stack addArrangedSubview:more];
        }
        if (stack.arrangedSubviews.lastObject != more) {
            [stack removeArrangedSubview:more];
            [stack addArrangedSubview:more];
        }
        NSMutableArray<UIAction *> *actions = [NSMutableArray array];
        NSMutableArray *signature = [NSMutableArray array];
        __weak UIButton *weakMore = more;
        for (NSUInteger index = plan.inlineCount; index < wanted.count; ++index) {
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
    CGRect frame = CGRectMake(plan.x, plan.y, plan.width, 44.0);
    if (!CGRectEqualToRect(stack.frame, frame)) stack.frame = frame;
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
            if (stack && !stack.hidden) stack.hidden = YES;
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
        if (stack.superview == receiver && receiver.subviews.lastObject != stack) [receiver bringSubviewToFront:stack];
        YTKACEReportLayoutState(receiver, stack.hidden ? @"no-free-slot" : @"local-row-visible");
    } @finally {
        objc_setAssociatedObject(receiver, YTKACELayoutInProgress, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSTimeInterval duration = NSProcessInfo.processInfo.systemUptime - started;
        static NSTimeInterval lastSlowLog;
        if (duration >= 0.05 && started - lastSlowLog >= 5) {
            lastSlowLog = started;
            NSLog(@"[YTKACE PlayerControls] slow layout %.0fms bounds=%@", duration * 1000, NSStringFromCGRect(receiver.bounds));
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
