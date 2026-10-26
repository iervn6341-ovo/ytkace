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
static const void *NativePresentationKey = &NativePresentationKey;
static const void *NativeTextRetryKey = &NativeTextRetryKey;
static IMP OriginalActionsForRenderers;
static IMP OriginalFactories[9];
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
static NSString *PlainString(id value) {
    if ([value isKindOfClass:NSAttributedString.class]) return [value string];
    if ([value isKindOfClass:NSString.class]) return value;
    id plain = Value(value,@"stringWithFormattingRemoved");
    if ([plain isKindOfClass:NSString.class]) return plain;
    id runs = Value(value,@"runsArray");
    if (![runs isKindOfClass:NSArray.class] || [runs count] > 32) return nil;
    NSMutableString *result = [NSMutableString string];
    for (id run in runs) {
        id text = Value(run,@"text");
        if ([text isKindOfClass:NSString.class]) [result appendString:text];
    }
    return result.length ? result : nil;
}
static NSString *Text(id object, NSString *key) {
    return PlainString(Value(object,key));
}
static NSString *Nonempty(NSString *text) {
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length ? text : nil;
}

// Recent YTActionSheetAction instances can keep a callable handler while exposing
// no title getter/ivar. Preserve presentation arguments at the native factories;
// the original factory and handler still run unchanged.
static id Capture(id action, id title, id subtitle, id value, id icon, id secondary, NSNumber *selected) {
    if (!action) return action;
    NSMutableDictionary *metadata = [objc_getAssociatedObject(action,NativePresentationKey) mutableCopy]
        ?: [NSMutableDictionary dictionary];
    for (NSArray *pair in @[@[@"title",title ?: NSNull.null],@[@"subtitle",subtitle ?: NSNull.null],
                            @[@"value",value ?: NSNull.null]]) {
        NSString *text = Nonempty(PlainString(pair[1]));
        if (text) metadata[pair[0]] = text;
    }
    if ([icon isKindOfClass:UIImage.class]) metadata[@"icon"] = icon;
    if ([secondary isKindOfClass:UIImage.class]) metadata[@"secondary"] = secondary;
    if (selected) metadata[@"selected"] = selected;
    objc_setAssociatedObject(action,NativePresentationKey,metadata,OBJC_ASSOCIATION_COPY_NONATOMIC);
    return action;
}
static id SimpleFactory(id cls, SEL cmd, id title, NSInteger style, id handler) {
    id action = ((id (*)(id,SEL,id,NSInteger,id))OriginalFactories[0])(cls,cmd,title,style,handler);
    return Capture(action,title,nil,nil,nil,nil,nil);
}
static id IconStyleFactory(id cls, SEL cmd, id title, id icon, NSInteger style, id handler) {
    id action = ((id (*)(id,SEL,id,id,NSInteger,id))OriginalFactories[1])(cls,cmd,title,icon,style,handler);
    return Capture(action,title,nil,nil,icon,nil,nil);
}
static id IconFactory(id cls, SEL cmd, id title, id icon, id handler) {
    id action = ((id (*)(id,SEL,id,id,id))OriginalFactories[2])(cls,cmd,title,icon,handler);
    return Capture(action,title,nil,nil,icon,nil,nil);
}
static id SubtitleFactory(id cls, SEL cmd, id title, id subtitle, id icon, id handler) {
    id action = ((id (*)(id,SEL,id,id,id,id))OriginalFactories[3])(cls,cmd,title,subtitle,icon,handler);
    return Capture(action,title,subtitle,nil,icon,nil,nil);
}
static id SubtitleIDFactory(id cls, SEL cmd, id title, id subtitle, id icon, id identifier, id handler) {
    id action = ((id (*)(id,SEL,id,id,id,id,id))OriginalFactories[4])(cls,cmd,title,subtitle,icon,identifier,handler);
    return Capture(action,title,subtitle,nil,icon,nil,nil);
}
static id DetailedFactory(id cls, SEL cmd, id title, id icon, id secondary, id identifier, id handler) {
    id action = ((id (*)(id,SEL,id,id,id,id,id))OriginalFactories[5])(cls,cmd,title,icon,secondary,identifier,handler);
    return Capture(action,title,nil,nil,icon,secondary,nil);
}
static id ValueFactory(id cls, SEL cmd, id title, id value, id icon, id identifier, id handler) {
    id action = ((id (*)(id,SEL,id,id,id,id,id))OriginalFactories[6])(cls,cmd,title,value,icon,identifier,handler);
    return Capture(action,title,nil,value,icon,nil,nil);
}
static id SelectableFactory(id cls, SEL cmd, id title, id subtitle, id icon, BOOL selected,
                           id label, id identifier, id handler) {
    id action = ((id (*)(id,SEL,id,id,id,BOOL,id,id,id))OriginalFactories[7])(
        cls,cmd,title,subtitle,icon,selected,label,identifier,handler);
    return Capture(action,title,subtitle,nil,icon,nil,@(selected));
}
static id ColoredFactory(id cls, SEL cmd, id title, id color, id icon, id iconColor, BOOL disable,
                        id identifier, id handler) {
    id action = ((id (*)(id,SEL,id,id,id,id,BOOL,id,id))OriginalFactories[8])(
        cls,cmd,title,color,icon,iconColor,disable,identifier,handler);
    return Capture(action,title,nil,nil,icon,nil,nil);
}

static NSString *ActionTitle(id model, UIButton *button, NSString **source) {
    for (NSString *key in @[@"title",@"attributedTitle",@"titleText",@"titleString"]) {
        NSString *title = Nonempty(Text(model,key));
        if (title) { *source = @"model"; return title; }
    }
    NSString *captured = objc_getAssociatedObject(model,NativePresentationKey)[@"title"];
    if (captured.length) { *source = @"factory"; return captured; }
    NSString *title = Nonempty(button.currentTitle) ?: Nonempty(button.currentAttributedTitle.string)
        ?: Nonempty(button.configuration.title) ?: Nonempty(button.titleLabel.text);
    if (title) { *source = @"button"; return title; }
    // Element-backed rows may render their text below the public UIButton.
    // Read the native text/accessibility data; do not replay screen coordinates
    // or invent labels from positional indexes or localized identifier guesses.
    NSMutableArray<UIView *> *queue = [NSMutableArray array];
    if (button) [queue addObject:button];
    for (NSString *key in @[@"titleLabel",@"elementView"]) {
        id view = Value(model,key);
        if ([view isKindOfClass:UIView.class]) [queue addObject:view];
        view = Value(button,key);
        if ([view isKindOfClass:UIView.class]) [queue addObject:view];
    }
    NSString *accessible = nil;
    for (NSUInteger index = 0; index < queue.count && index < 48; ++index) {
        UIView *view = queue[index];
        if ([view isKindOfClass:UILabel.class]) {
            title = Nonempty(((UILabel *)view).text) ?: Nonempty(((UILabel *)view).attributedText.string);
            if (title) { *source = @"label"; return title; }
        }
        id node = Value(view,@"asyncdisplaykit_node");
        title = Nonempty(Text(node,@"attributedText")) ?: Nonempty(Text(node,@"text"));
        if (title) { *source = @"node"; return title; }
        accessible = accessible ?: Nonempty(view.accessibilityLabel) ?: Nonempty(Text(node,@"accessibilityLabel"));
        if (queue.count < 48) [queue addObjectsFromArray:view.subviews];
    }
    if (accessible) { *source = @"accessibility"; return accessible; }
    return nil;
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
    NSArray<NSString *> *selectors = @[
        @"actionWithTitle:style:handler:", @"actionWithTitle:iconImage:style:handler:",
        @"actionWithTitle:iconImage:handler:", @"actionWithTitle:subtitle:iconImage:handler:",
        @"actionWithTitle:subtitle:iconImage:accessibilityIdentifier:handler:",
        @"actionWithTitle:iconImage:secondaryIconImage:accessibilityIdentifier:handler:",
        @"actionWithTitle:currentValue:iconImage:accessibilityIdentifier:handler:",
        @"actionWithTitle:subtitle:iconImage:visiblySelected:accessibilityLabel:accessibilityIdentifier:handler:",
        @"actionWithTitle:titleColor:iconImage:iconColor:disableAutomaticButtonColor:accessibilityIdentifier:handler:"];
    const IMP factories[] = {(IMP)SimpleFactory,(IMP)IconStyleFactory,(IMP)IconFactory,(IMP)SubtitleFactory,
        (IMP)SubtitleIDFactory,(IMP)DetailedFactory,(IMP)ValueFactory,(IMP)SelectableFactory,(IMP)ColoredFactory};
    for (NSUInteger index = 0; index < selectors.count; ++index)
        YTKACEInstallClassHook(@"YTActionSheetAction",selectors[index],factories[index],&OriginalFactories[index]);
}

NSArray<NSDictionary *> *YTKACENativePlayerActions(UIViewController *controller) {
    // These links are used by YouTube's default/action/contextual sheet models.
    // Inspect a bounded controller/model graph, never infer actions from labels
    // or replay taps into the old clipped screen coordinates.
    objc_setAssociatedObject(controller,NativeTextRetryKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
    NSMutableDictionary<NSString *,NSNumber *> *titleSources = [NSMutableDictionary dictionary];
    for (id model in models) {
        UIButton *button = Value(model,@"button");
        if (![button isKindOfClass:UIButton.class]) button = nil;
        NSString *titleSource = nil;
        NSString *title = ActionTitle(model,button,&titleSource);
        NSDictionary *captured = objc_getAssociatedObject(model,NativePresentationKey);
        BOOL enabled = Flag(model,@"isEnabled",button ? button.enabled : YES);
        dispatch_block_t handler = ActionHandler(model);
        // All-or-nothing: preserve special/custom rows in their native sheet.
        if (!title.length || (enabled && !handler)) {
            BOOL retryText = !title.length && (!enabled || handler);
            objc_setAssociatedObject(controller,NativeTextRetryKey,@(retryText),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] %{public}@ reason=incomplete-action index=%lu class=%{public}@ title=%d handler=%d buttonClass=%{public}@",
                retryText ? @"decode-deferred" : @"native fallback",(unsigned long)actions.count,
                NSStringFromClass([model class]),title.length != 0,handler != nil,
                button ? NSStringFromClass(button.class) : @"none");
            return nil;
        }
        NSMutableDictionary *action = [@{@"title":title,@"enabled":@(enabled),
            @"selected":@(Flag(model,@"visiblySelected",captured[@"selected"] ? [captured[@"selected"] boolValue] : button.selected))} mutableCopy];
        titleSources[titleSource] = @(titleSources[titleSource].unsignedIntegerValue + 1);
        if (handler) action[@"handler"] = handler;
        for (NSString *key in @[@"subtitle",@"currentValue"]) {
            NSString *text = Text(model,key) ?: captured[[key isEqual:@"currentValue"] ? @"value" : key];
            if (text.length) action[[key isEqual:@"currentValue"] ? @"value" : key] = text;
        }
        for (NSArray *keys in @[@[@"iconImage",@"icon"],@[@"secondaryIconImage",@"secondary"]]) {
            id image = Value(model,keys[0]) ?: captured[keys[1]];
            if ([image isKindOfClass:UIImage.class]) action[keys[1]] = image;
        }
        [actions addObject:action];
    }
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] decoded actions=%lu titleSources=%{public}@",
        (unsigned long)actions.count,titleSources);
    return actions;
}

BOOL YTKACENativeMenuNeedsTextRetry(UIViewController *controller) {
    return [objc_getAssociatedObject(controller,NativeTextRetryKey) boolValue];
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
