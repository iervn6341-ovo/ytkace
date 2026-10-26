#import "NativePlayerMenu.h"
#import "SystemMenu.h"
#import "../Runtime/Hooking.h"
#import "../Runtime/Preferences.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>
#include <string.h>

static const void *NativeRouteKey = &NativeRouteKey;
static const void *NativeOwnerKey = &NativeOwnerKey;
static IMP OriginalActionsForRenderers;
@interface YTKACENativeMenuOwner : NSObject
@property(nonatomic, weak) id value;
@end
@implementation YTKACENativeMenuOwner @end

static id Value(id object, NSString *name) {
    if (!object) return nil;
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (signature.numberOfArguments == 2 && signature.methodReturnType[0] == '@')
        return ((id (*)(id,SEL))objc_msgSend)(object,selector);
    for (NSString *key in @[name,[@"_" stringByAppendingString:name]]) {
        Ivar ivar = class_getInstanceVariable([object class],key.UTF8String);
        if (ivar && ivar_getTypeEncoding(ivar)[0] == '@') return object_getIvar(object,ivar);
    }
    return nil;
}
static NSString *Text(id object, NSString *key) {
    id value = Value(object,key);
    if ([value isKindOfClass:NSAttributedString.class]) return [value string];
    return [value isKindOfClass:NSString.class] ? value : nil;
}
static BOOL Flag(id object, NSString *key, BOOL fallback) {
    SEL selector = NSSelectorFromString(key);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (signature.numberOfArguments == 2 && strchr("Bc",signature.methodReturnType[0]))
        return ((BOOL (*)(id,SEL))objc_msgSend)(object,selector);
    return fallback;
}

// Clang's published Apple Blocks ABI carries the actual callable signature.
// Native factories have used both ^{} and ^(id action); never guess the arity.
// https://clang.llvm.org/docs/Block-ABI-Apple.html
struct NativeBlock {
    void *isa;
    int flags, reserved;
    void *invoke;
    const uintptr_t *descriptor;
};
static NSMethodSignature *HandlerSignature(id handler) {
    Class block = NSClassFromString(@"NSBlock");
    if (!block || ![handler isKindOfClass:block]) return nil;
    const NativeBlock *literal = (__bridge const NativeBlock *)handler;
    if (!(literal->flags & (1 << 30)) || !literal->descriptor) return nil;
    const uintptr_t *entry = literal->descriptor + 2;
    if (literal->flags & (1 << 25)) entry += 2;
    const char *signature = (const char *)*entry;
    return signature ? [NSMethodSignature signatureWithObjCTypes:signature] : nil;
}
static dispatch_block_t ActionHandler(id action) {
    dispatch_block_t route = objc_getAssociatedObject(action,NativeRouteKey);
    if (route) return route;
    id handler = Value(action,@"handler");
    NSMethodSignature *signature = HandlerSignature(handler);
    if (!signature || signature.methodReturnType[0] != 'v') return nil;
    if (signature.numberOfArguments == 1) return [^{ ((void (^)(void))handler)(); } copy];
    if (signature.numberOfArguments == 2 && [signature getArgumentTypeAtIndex:1][0] == '@')
        return [^{ ((void (^)(id))handler)(action); } copy];
    return nil;
}

static NSString *ItemIdentifier(id renderer) {
    id options = Value(Value(renderer,@"elementRenderer"),@"compatibilityOptions");
    SEL message = NSSelectorFromString(@"messageForFieldNumber:");
    NSMethodSignature *signature = [options methodSignatureForSelector:message];
    if (signature.numberOfArguments == 3 && signature.methodReturnType[0] == '@' &&
        strchr("iI",[signature getArgumentTypeAtIndex:2][0])) {
        id extension = ((id (*)(id,SEL,int32_t))objc_msgSend)(options,message,396644439);
        NSString *identifier = Text(extension,@"menuItemIdentifier");
        if (identifier.length) return identifier;
    }
    return Text(Value(renderer,@"menuNavigationItemRenderer"),@"menuItemIdentifier");
}

static id ActionsForRenderers(id receiver, SEL selector, NSArray *renderers, UIView *source,
                               id entry, BOOL logItems, id responder) {
    id actions = OriginalActionsForRenderers ? ((id (*)(id,SEL,id,id,id,BOOL,id))OriginalActionsForRenderers)(
        receiver,selector,renderers,source,entry,logItems,responder) : nil;
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Interface.SystemMenus") ||
        ![actions isKindOfClass:NSArray.class] || ![renderers isKindOfClass:NSArray.class] ||
        [actions count] < renderers.count) return actions;
    NSDictionary *routes = @{@"menu_item_video_quality":@"didPressVideoQuality:",
        @"menu_item_playback_speed":@"didPressVarispeed:",@"menu_item_audio_track":@"didPressAudioTrackSwitch:"};
    for (NSUInteger index = 0; index < renderers.count; ++index) {
        NSString *identifier = ItemIdentifier(renderers[index]);
        NSString *name = identifier ? routes[identifier] : nil;
        SEL route = name ? NSSelectorFromString(name) : NULL;
        if (!route || ![responder respondsToSelector:route]) continue;
        NSMethodSignature *signature = [responder methodSignatureForSelector:route];
        if (signature.numberOfArguments != 3 || signature.methodReturnType[0] != 'v' ||
            [signature getArgumentTypeAtIndex:2][0] != '@') continue;
        __weak id weakResponder = responder;
        __weak UIView *weakSource = source;
        dispatch_block_t handler = ^{
            id target = weakResponder;
            if ([target respondsToSelector:route]) ((void (*)(id,SEL,id))objc_msgSend)(target,route,weakSource);
        };
        // Element-backed quality/speed rows can dispatch through their view
        // instead of action.handler. Route verified native identifiers through
        // the same player methods as the shortcuts, without changing native rows.
        objc_setAssociatedObject(actions[index],NativeRouteKey,handler,OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    return actions;
}

void YTKACEInstallNativePlayerMenuAdapter(void) {
    YTKACEInstallInstanceHook(@"YTMenuController",
        @"actionsForRenderers:fromView:entry:shouldLogItems:firstResponder:",
        (IMP)ActionsForRenderers,&OriginalActionsForRenderers);
}

NSArray<NSDictionary *> *YTKACENativePlayerActions(UIViewController *controller) {
    // These links are used by YouTube's default/action/contextual sheet models.
    // Inspect a bounded controller/model graph, never infer actions from labels
    // or replay taps into the old clipped screen coordinates.
    [controller loadViewIfNeeded];
    NSMutableArray *queue = [NSMutableArray arrayWithObject:controller];
    NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    NSArray *models = nil;
    for (NSUInteger index = 0; index < queue.count && index < 32; ++index) {
        id object = queue[index];
        if ([seen containsObject:object]) continue;
        [seen addObject:object];
        id candidate = Value(object,@"actions");
        if ([candidate isKindOfClass:NSArray.class] && [candidate count]) {
            models = candidate;
            YTKACENativeMenuOwner *owner = [YTKACENativeMenuOwner new]; owner.value = object;
            objc_setAssociatedObject(controller,NativeOwnerKey,owner,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            break;
        }
        if ([object isKindOfClass:UIViewController.class]) [queue addObjectsFromArray:[object childViewControllers]];
        for (NSString *key in @[@"contentViewController",@"actionsController",@"delegate",@"actionSheetController"])
            if (id next = Value(object,key)) [queue addObject:next];
    }
    if (!models.count || models.count > 100) {
        os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] native fallback reason=no-action-model class=%{public}@",
            NSStringFromClass(controller.class));
        return nil;
    }
    NSMutableArray *actions = [NSMutableArray array];
    for (id model in models) {
        NSString *title = Text(model,@"title");
        UIButton *button = Value(model,@"button");
        if (![button isKindOfClass:UIButton.class]) button = nil;
        BOOL enabled = Flag(model,@"isEnabled",button ? button.enabled : YES);
        dispatch_block_t handler = ActionHandler(model);
        // All-or-nothing: preserve special/custom rows in their native sheet.
        if (!title.length || (enabled && !handler)) {
            os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] native fallback reason=incomplete-action index=%lu class=%{public}@ title=%d handler=%d",
                (unsigned long)actions.count,NSStringFromClass([model class]),title.length != 0,handler != nil);
            return nil;
        }
        NSMutableDictionary *action = [@{@"title":title,@"enabled":@(enabled),
            @"selected":@(Flag(model,@"visiblySelected",button.selected))} mutableCopy];
        if (handler) action[@"handler"] = handler;
        for (NSString *key in @[@"subtitle",@"currentValue"]) {
            NSString *text = Text(model,key);
            if (text.length) action[[key isEqual:@"currentValue"] ? @"value" : key] = text;
        }
        for (NSArray *keys in @[@[@"iconImage",@"icon"],@[@"secondaryIconImage",@"secondary"]]) {
            id image = Value(model,keys[0]);
            if ([image isKindOfClass:UIImage.class]) action[keys[1]] = image;
        }
        [actions addObject:action];
    }
    return actions;
}

@interface YTKACENativeMenuSession : NSObject
@property(nonatomic, weak) UIViewController *native;
@property(nonatomic) CGFloat originalAlpha;
@property(nonatomic, copy) NSArray<UIView *> *backdrops;
@property(nonatomic, copy) NSArray<NSNumber *> *backdropAlphas;
@property(nonatomic) BOOL finished;
- (void)finish:(dispatch_block_t)action;
@end
@implementation YTKACENativeMenuSession
- (void)restore {
    self.native.view.alpha = self.originalAlpha;
    [self.backdrops enumerateObjectsUsingBlock:^(UIView *view, NSUInteger index, BOOL *stop) {
        (void)stop; view.alpha = self.backdropAlphas[index].doubleValue;
    }];
    self.backdrops = nil; self.backdropAlphas = nil;
}
- (void)finish:(dispatch_block_t)action {
    if (self.finished) return;
    self.finished = YES;
    UIViewController *native = self.native;
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] adapted close selected=%d",action != nil);
    // Keep the real sheet's appearance, dismissal and transitioning delegate.
    // Its original presentation was never changed to a popover. Close it before
    // running an action which can synchronously present the next native page.
    YTKACENativeMenuOwner *box = objc_getAssociatedObject(native,NativeOwnerKey);
    id owner = box.value;
    SEL dismiss = @selector(dismissViewControllerAnimated:completion:);
    NSMethodSignature *signature = [owner methodSignatureForSelector:dismiss];
    BOOL nativeOwner = owner && ![owner isKindOfClass:UIViewController.class] &&
        signature.numberOfArguments == 4 && signature.methodReturnType[0] == 'v' &&
        strchr("Bc",[signature getArgumentTypeAtIndex:2][0]) &&
        [signature getArgumentTypeAtIndex:3][0] == '@';
    void (^completion)(void) = ^{ [self restore]; if (action) action(); };
    if (native.presentingViewController && !native.isBeingDismissed && nativeOwner) {
        // YTDefaultSheetController also owns dismissal state used by quality
        // coordinators. Use its verified close API when exposed, not just UIKit.
        ((void (*)(id,SEL,BOOL,id))objc_msgSend)(owner,dismiss,NO,completion);
    } else if (native.presentingViewController && !native.isBeingDismissed)
        [native dismissViewControllerAnimated:NO completion:completion];
    else { [self restore]; if (action) action(); }
}
@end

void YTKACEPresentAdaptedPlayerMenu(UIViewController *controller, UIView *source, NSArray<NSDictionary *> *actions) {
    YTKACENativeMenuSession *session = [YTKACENativeMenuSession new];
    session.native = controller;
    session.originalAlpha = controller.view.alpha;
    // The native sheet remains presented, retaining the callbacks/state used by
    // quality and submenu controllers. Its content is replaced visually only.
    NSMutableArray *backdrops = [NSMutableArray array], *alphas = [NSMutableArray array];
    UIView *container = controller.presentationController.containerView;
    for (UIView *view in container.subviews) {
        if (view == source || [source isDescendantOfView:view]) continue;
        [backdrops addObject:view]; [alphas addObject:@(view.alpha)]; view.alpha = 0;
    }
    session.backdrops = backdrops; session.backdropAlphas = alphas;
    controller.view.alpha = 0;
    NSMutableArray *adapted = [NSMutableArray array];
    for (NSDictionary *item in actions) {
        NSMutableDictionary *copy = [item mutableCopy];
        dispatch_block_t original = item[@"handler"];
        if (original) copy[@"handler"] = [^{ [session finish:original]; } copy];
        [adapted addObject:copy];
    }
    if (!YTKACEPresentSystemMenuWithDismissal(controller,source,controller.title,nil,adapted,^(BOOL selected) {
        if (!selected) [session finish:nil];
    })) {
        [session restore];
        os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] native fallback reason=anchor-or-presenter");
        return;
    }
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] adapted class=%{public}@ actions=%lu",
        NSStringFromClass(controller.class),(unsigned long)actions.count);
}
