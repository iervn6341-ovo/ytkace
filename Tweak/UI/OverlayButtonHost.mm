#import "OverlayButtonHost.h"
#import "../YTKACE.h"
#import "../Runtime/Hooking.h"
#import "../Runtime/Preferences.h"
#import "../Runtime/Localization.h"
#include "OverlayLayoutPolicy.hpp"

#import <math.h>
#import <objc/runtime.h>
#import <objc/message.h>

static IMP OriginalControlsOverlayLayout;
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

static BOOL YTKACEKeepControlsVisible(void) {
    return YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.AlwaysShowControls");
}

static void YTKACESetHostedControlsHidden(UIView *view, BOOL hidden) {
    if ([view.accessibilityIdentifier isEqualToString:@"YTKACEOverlayControls"]) {
        BOOL visible = !hidden;
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
    visible = visible || YTKACEKeepControlsVisible();
    if (OriginalControlsSetOverlayVisible != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalControlsSetOverlayVisible)(receiver, selector, visible);
    }
    YTKACEUpdateHostedVisibility(receiver, visible);
}

static void YTKACEControlsSetControlsVisible(UIView *receiver, SEL selector, BOOL visible) {
    visible = visible || YTKACEKeepControlsVisible();
    if (OriginalControlsSetControlsVisible != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalControlsSetControlsVisible)(receiver, selector, visible);
    }
    YTKACEUpdateHostedVisibility(receiver, visible);
}

static void YTKACEVideoSetOverlayVisible(UIView *receiver, SEL selector, BOOL visible) {
    visible = visible || YTKACEKeepControlsVisible();
    if (OriginalVideoSetOverlayVisible != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalVideoSetOverlayVisible)(receiver, selector, visible);
    }
    YTKACEUpdateHostedVisibility(receiver, visible);
}

static void YTKACEVideoSetControlsVisible(UIView *receiver, SEL selector, BOOL visible) {
    visible = visible || YTKACEKeepControlsVisible();
    if (OriginalVideoSetControlsVisible != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalVideoSetControlsVisible)(receiver, selector, visible);
    }
    YTKACEUpdateHostedVisibility(receiver, visible);
}

static void YTKACEControlsSetHidden(UIView *receiver, SEL selector, BOOL hidden) {
    hidden = hidden && !YTKACEKeepControlsVisible();
    if (OriginalControlsSetHidden != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalControlsSetHidden)(receiver, selector, hidden);
    }
    YTKACEUpdateHostedVisibility(receiver, !hidden);
}

static UIStackView *YTKACEStackForOverlay(UIView *overlay) {
    UIStackView *stack = objc_getAssociatedObject(overlay, YTKACEOverlayStackAssociation);
    if (stack != nil) {
        return stack;
    }

    stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.distribution = UIStackViewDistributionFill;
    stack.spacing = 4.0;
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

static UIButton *YTKACENativePlayerButton(UIView *overlay, NSString *identifier,
                                         NSString *symbolName) {
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration
        configurationWithPointSize:24.0 weight:UIImageSymbolWeightRegular];
    UIImage *image = YTKACEPlayerGlyph([UIImage systemImageNamed:symbolName withConfiguration:configuration]);
    UIButton *button = nil;
    SEL factory = NSSelectorFromString(@"buttonWithImage:accessibilityLabel:verticalContentPadding:");
    if ([overlay respondsToSelector:factory]) {
        id candidate = ((id (*)(id, SEL, id, id, CGFloat))objc_msgSend)(
            overlay, factory, image, identifier, 10.0);
        if ([candidate isKindOfClass:UIButton.class]) button = candidate;
    }
    if (button == nil) {
        Class nativeClass = NSClassFromString(@"YTQTMButton");
        SEL iconFactory = NSSelectorFromString(@"iconButton");
        if ([nativeClass respondsToSelector:iconFactory]) {
            id candidate = ((id (*)(id, SEL))objc_msgSend)(nativeClass, iconFactory);
            if ([candidate isKindOfClass:UIButton.class]) button = candidate;
        }
    }
    if (button == nil) button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.accessibilityIdentifier = identifier;
    button.accessibilityLabel = identifier;
    button.tintColor = UIColor.whiteColor;
    [button setImage:image forState:UIControlStateNormal];
    [button setPreferredSymbolConfiguration:configuration forImageInState:UIControlStateNormal];
    button.imageView.contentMode = UIViewContentModeScaleAspectFit;
    button.clipsToBounds = YES;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.widthAnchor constraintEqualToConstant:44.0].active = YES;
    [button.heightAnchor constraintEqualToConstant:44.0].active = YES;
    SEL sizing = NSSelectorFromString(@"setSizeWithPaddingAndInsets:");
    if ([button respondsToSelector:sizing]) ((void (*)(id, SEL, BOOL))objc_msgSend)(button, sizing, NO);
    SEL hitTarget = NSSelectorFromString(@"setMinHitTargetSize:");
    if ([button respondsToSelector:hitTarget]) ((void (*)(id, SEL, CGFloat))objc_msgSend)(button, hitTarget, 44.0);
    SEL feedback = NSSelectorFromString(@"enableNewTouchFeedback");
    if ([button respondsToSelector:feedback]) ((void (*)(id, SEL))objc_msgSend)(button, feedback);
    return button;
}

UIButton *YTKACEOverlayButton(UIStackView *stack,
                              NSString *identifier,
                              NSString *symbolName,
                              id target,
                              SEL action) {
    for (UIView *view in stack.arrangedSubviews) {
        if ([view.accessibilityIdentifier isEqualToString:identifier] &&
            [view isKindOfClass:UIButton.class]) {
            return (UIButton *)view;
        }
    }

    UIButton *button = YTKACENativePlayerButton(stack.superview, identifier, symbolName);
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    __weak id weakTarget = target;
    void (^invoke)(UIButton *) = ^(UIButton *sender) {
        id strongTarget = weakTarget;
        if (strongTarget != nil) [sender sendAction:action to:strongTarget forEvent:nil];
    };
    objc_setAssociatedObject(button, YTKACEPlayerActionAssociation,
                             invoke, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [stack addArrangedSubview:button];
    return button;
}

static void YTKACEAvoidNativeControls(UIView *view, UIView *overlay,
                                      UIStackView *stack, CGRect band,
                                      CGFloat *left) {
    if (view == stack || view.hidden || view.alpha < 0.05) return;
    if ([view isKindOfClass:UIControl.class]) {
        CGRect frame = [view convertRect:view.bounds toView:overlay];
        // Ignore full-player tap-catcher buttons, not actual transport controls.
        if (CGRectGetWidth(frame) <= 100 && CGRectGetHeight(frame) <= 100 &&
            CGRectIntersectsRect(frame, band)) *left = MAX(*left, CGRectGetMaxX(frame) + 4.0);
    }
    for (UIView *child in view.subviews) YTKACEAvoidNativeControls(child, overlay, stack, band, left);
}

static void YTKACELayoutPlayerButtons(UIView *overlay, UIStackView *stack) {
    NSMutableArray<UIButton *> *wanted = [NSMutableArray array];
    UIButton *more = nil;
    for (UIView *view in stack.arrangedSubviews) {
        if (![view isKindOfClass:UIButton.class]) continue;
        UIButton *button = (UIButton *)view;
        if ([button.accessibilityIdentifier isEqualToString:YTKACEOverflowIdentifier]) {
            more = button;
            more.hidden = YES;
            continue;
        }
        for (NSNumber *state in @[@(UIControlStateNormal), @(UIControlStateSelected), @(UIControlStateHighlighted)]) {
            UIImage *image = [button imageForState:state.unsignedIntegerValue];
            UIImage *glyph = YTKACEPlayerGlyph(image);
            if (image != glyph) [button setImage:glyph forState:state.unsignedIntegerValue];
        }
        if (!button.hidden) [wanted addObject:button];
    }
    CGRect safe = UIEdgeInsetsInsetRect(overlay.bounds, overlay.safeAreaInsets);
    CGFloat left = CGRectGetMinX(safe) + 8.0;
    CGFloat right = CGRectGetMaxX(safe) - 8.0;
    CGFloat top = CGRectGetMinY(safe) + 50.0;
    UIView *gear = YTKACEOverflowControl(overlay) ?: YTKACEFindSettingsControl(overlay, stack);
    if (gear != nil) {
        CGRect frame = [gear convertRect:gear.bounds toView:overlay];
        top = MAX(CGRectGetMinY(safe) + 4.0, CGRectGetMaxY(frame) + 4.0);
        right = MIN(right, CGRectGetMidX(frame) + 22.0);
    }
    CGRect band = CGRectMake(left, top, MAX(0, right - left), 44.0);
    YTKACEAvoidNativeControls(overlay, overlay, stack, band, &left);
    auto plan = ytkace::planOverlay(left, right, top, CGRectGetMaxY(safe) - 8.0, wanted.count);
    stack.hidden = !plan.fits;
    if (!plan.fits) return;
    for (NSUInteger index = plan.inlineCount; index < wanted.count; ++index) wanted[index].hidden = YES;
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
                // Invoke only the feature action, not YTQTMButton's internal
                // feedback targets. A visible sender keeps iPad popovers valid.
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
        more.hidden = NO;
    }
    stack.frame = CGRectMake(plan.x, plan.y, plan.width, 44.0);
}

static void YTKACEControlsOverlayLayout(UIView *receiver, SEL selector) {
    if (OriginalControlsOverlayLayout != NULL) {
        ((void (*)(id, SEL))OriginalControlsOverlayLayout)(receiver, selector);
    }

    UIStackView *stack = YTKACEStackForOverlay(receiver);
    NSArray<NSDictionary *> *configurators = nil;
    @synchronized (YTKACEOverlayConfigurators) {
        configurators = [YTKACEOverlayConfigurators copy];
    }
    for (NSDictionary *entry in configurators) {
        YTKACEOverlayConfigurator configurator = entry[@"block"];
        configurator(receiver, stack);
    }
    YTKACELayoutPlayerButtons(receiver, stack);
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
