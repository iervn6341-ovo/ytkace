#import "NativePlayerMenu.h"
#import "SystemMenu.h"
#import "PlayerMenuPresentation.h"
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
static const void *NativeItemIdentifierKey = &NativeItemIdentifierKey;
static const void *NativeTextProbeKey = &NativeTextProbeKey;
static const void *NativeOutsideTapKey = &NativeOutsideTapKey;
static const void *NativeControlModelKey = &NativeControlModelKey;
static const void *NativeRowsPendingKey = &NativeRowsPendingKey;
static IMP OriginalSetButton;
static IMP OriginalActionsForRenderers;
static IMP OriginalFactories[9];
@interface YTKACENativeMenuOwner : NSObject
@property(nonatomic, weak) id value;
@end
@implementation YTKACENativeMenuOwner @end
static void RememberControl(id action, id button) {
    if (![button isKindOfClass:UIView.class]) return;
    YTKACENativeMenuOwner *box = [YTKACENativeMenuOwner new]; box.value = action;
    objc_setAssociatedObject(button,NativeControlModelKey,box,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void SetButton(id receiver, SEL cmd, id button) {
    if (OriginalSetButton) ((void (*)(id,SEL,id))OriginalSetButton)(receiver,cmd,button);
    RememberControl(receiver,button);
}
NSString *YTKACENativeControlTitle(UIView *source) {
    for (NSUInteger depth = 0; source && depth < 8; ++depth,source = source.superview) {
        YTKACENativeMenuOwner *box = objc_getAssociatedObject(source,NativeControlModelKey);
        NSString *title = objc_getAssociatedObject(box.value,NativePresentationKey)[@"title"];
        if (title.length) return title;
    }
    return nil;
}

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
    RememberControl(action,Value(action,@"button"));
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

static NSString *ElementTitle(id model, id button, NSString **source) {
    objc_setAssociatedObject(model,NativeTextProbeKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSMutableArray *queue = [NSMutableArray array], *depths = [NSMutableArray array];
    NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    NSMutableDictionary<NSString *,NSNumber *> *classes = [NSMutableDictionary dictionary];
    auto enqueue = [&](id object, NSUInteger depth) {
        if (!object || object == NSNull.null || depth > 8 || queue.count >= 128 || [seen containsObject:object]) return;
        [seen addObject:object]; [queue addObject:object]; [depths addObject:@(depth)];
    };
    enqueue(button,0);
    for (NSString *key in @[@"titleLabel",@"elementView"]) {
        enqueue(Value(model,key),0); enqueue(Value(button,key),0);
    }
    NSString *accessible = nil;
    NSUInteger axContainers = 0;
    for (NSUInteger index = 0; index < queue.count; ++index) {
        id object = queue[index];
        NSUInteger depth = [depths[index] unsignedIntegerValue];
        NSString *name = NSStringFromClass([object class]) ?: @"unknown";
        classes[name] = @(classes[name].unsignedIntegerValue + 1);
        NSString *text = Nonempty(Text(object,@"attributedText")) ?: Nonempty(Text(object,@"text"));
        if (text) { *source = [object isKindOfClass:UILabel.class] ? @"label" : @"node"; return text; }
        accessible = accessible ?: Nonempty(Text(object,@"accessibilityLabel"))
            ?: Nonempty(Text(object,@"accessibilityAttributedLabel"));
        // ELM renders text in node children and virtual accessibility elements,
        // which are not necessarily UIView descendants or UILabel instances.
        // ASDisplayNode exposes controller/yogaChildren; ELMNodeController
        // exposes children/materializedInstance. Layer-backed text can live
        // there even when subnodes and UIView descendants are empty.
        for (NSString *key in @[@"keepalive_node",@"asyncdisplaykit_node",@"node",@"elementView",
                                @"controller",@"materializedInstance",@"element"])
            enqueue(Value(object,key),depth + 1);
        BOOL hasAccessibilityArray = NO;
        for (NSString *key in @[@"subviews",@"subnodes",@"yogaChildren",@"children",@"accessibilityElements"]) {
            id children = Value(object,key);
            if (![children isKindOfClass:NSArray.class]) continue;
            if ([key isEqual:@"accessibilityElements"] && [children count]) { axContainers++; hasAccessibilityArray = YES; }
            for (id child in children) {
                enqueue(child,depth + 1);
                if (queue.count >= 128) break;
            }
        }
        SEL countSelector = @selector(accessibilityElementCount);
        SEL elementSelector = @selector(accessibilityElementAtIndex:);
        NSMethodSignature *countSignature = [object methodSignatureForSelector:countSelector];
        NSMethodSignature *elementSignature = [object methodSignatureForSelector:elementSelector];
        if (!hasAccessibilityArray && countSignature.numberOfArguments == 2 &&
            countSignature.methodReturnType[0] == @encode(NSInteger)[0] &&
            elementSignature.numberOfArguments == 3 && elementSignature.methodReturnType[0] == '@' &&
            [elementSignature getArgumentTypeAtIndex:2][0] == @encode(NSInteger)[0]) {
            @try {
                NSInteger count = ((NSInteger (*)(id,SEL))objc_msgSend)(object,countSelector);
                if (count > 0 && count <= 32) {
                    axContainers++;
                    for (NSInteger item = 0; item < count && queue.count < 128; ++item)
                        enqueue(((id (*)(id,SEL,NSInteger))objc_msgSend)(object,elementSelector,item),depth + 1);
                }
            } @catch (__unused NSException *exception) { /* A virtual container may change while queried. */ }
        }
    }
    if (accessible) { *source = @"accessibility"; return accessible; }
    // Schema only: never log the actual displayed/accessibility text.
    objc_setAssociatedObject(model,NativeTextProbeKey,@{@"classes":classes,@"objects":@(queue.count),
        @"accessibilityContainers":@(axContainers),@"capped":@(queue.count >= 128)},OBJC_ASSOCIATION_COPY_NONATOMIC);
    return nil;
}

static NSString *ActionTitle(id model, id button, NSString **source) {
    for (NSString *key in @[@"title",@"attributedTitle",@"titleText",@"titleString"]) {
        NSString *title = Nonempty(Text(model,key));
        if (title) { *source = @"model"; return title; }
    }
    NSDictionary *metadata = objc_getAssociatedObject(model,NativePresentationKey);
    NSString *captured = metadata[@"title"];
    if (captured.length) { *source = metadata[@"textSource"] ?: @"factory"; return captured; }
    NSString *title = Nonempty(Text(button,@"currentTitle")) ?: Nonempty(Text(button,@"currentAttributedTitle"))
        ?: Nonempty(Text(Value(button,@"configuration"),@"title")) ?: Nonempty(Text(Value(button,@"titleLabel"),@"text"));
    if (title) { *source = @"button"; return title; }
    // Element-backed rows may render their text below the public UIButton.
    // Read the native text/accessibility data; do not replay screen coordinates
    // or invent labels from positional indexes or localized identifier guesses.
    return ElementTitle(model,button,source);
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

// ELM controls may own the real navigation dispatch while action.handler is a
// placeholder. Use one registered native activation event, never both paths.
static dispatch_block_t ControlActivation(id button) {
    if (![button isKindOfClass:UIControl.class]) return nil;
    UIControl *control = button;
    UIControlEvents event = 0;
    for (NSNumber *candidate in @[@(UIControlEventTouchUpInside), @(UIControlEventPrimaryActionTriggered)]) {
        UIControlEvents value = candidate.unsignedIntegerValue;
        if (control.allControlEvents & value) { event = value; break; }
    }
    if (!event) return nil;
    return [^{
        os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] native control-event class=%{public}@ event=%lu targets=%lu",
            NSStringFromClass(control.class),(unsigned long)event,(unsigned long)control.allTargets.count);
        [control sendActionsForControlEvents:event];
    } copy];
}

static void InvokeELMTap(id command);
// The observed ELM row has two independent paths: its content tap executes a
// command, while GOODialogView.actionButtonDidTap: only dismisses the dialog.
// Resolve one actual, enabled content command; never synthesize gesture state.
static id ELMTapCommand(id button, BOOL *unsupported) {
    Class rowClass = NSClassFromString(@"YTMenuItemElementsMDCButton");
    Class handlerClass = NSClassFromString(@"ELMTouchCommandPropertiesHandler");
    if (!rowClass || !handlerClass || ![button isKindOfClass:rowClass]) return nil;
    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObject:button];
    id command = nil;
    for (NSUInteger index = 0; index < views.count && index < 64; index++) {
        UIView *view = views[index];
        for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
            if (![gesture isKindOfClass:UITapGestureRecognizer.class] ||
                ![gesture.delegate isKindOfClass:handlerClass]) continue;
            UITapGestureRecognizer *tap = (id)gesture;
            id candidate = gesture.delegate;
            NSMethodSignature *signature = [candidate methodSignatureForSelector:NSSelectorFromString(@"handleTap")];
            if (!gesture.enabled || view.hidden || view.alpha < 0.05 ||
                tap.numberOfTapsRequired != 1 || tap.numberOfTouchesRequired != 1 ||
                signature.numberOfArguments != 2 || signature.methodReturnType[0] != 'v' ||
                (command && command != candidate)) {
                *unsupported = YES; return nil;
            }
            command = candidate;
        }
        for (UIView *child in view.subviews) {
            if (views.count >= 64) { *unsupported = YES; return nil; }
            [views addObject:child];
        }
    }
    return command;
}

// A trace owns only diagnostics. Weak references leave the native lifetime intact.
@interface YTKACENativeMenuTrace : NSObject
@property(nonatomic) NSUInteger identifier, presentationRequests, selectorCalls, uiActionCalls, elmCalls;
@property(nonatomic) BOOL handlerReturned;
@property(nonatomic) NSTimeInterval start;
@property(nonatomic, weak) UIViewController *native;
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, weak) UIControl *control;
@property(nonatomic, weak) id owner;
@end
@implementation YTKACENativeMenuTrace @end
static YTKACENativeMenuTrace *ActiveTrace, *RecentTrace;
static NSUInteger TraceSequence;
static NSString *TraceClass(id value) { return value ? NSStringFromClass([value class]) : @"none"; }
static NSString *TraceControllerChain(UIWindow *window) {
    NSMutableArray *names = [NSMutableArray array];
    UIViewController *current = window.rootViewController;
    for (NSUInteger depth = 0; current && depth < 10; depth++, current = current.presentedViewController) {
        NSString *name = TraceClass(current);
        if ([current isKindOfClass:UINavigationController.class])
            name = [name stringByAppendingFormat:@"(%@)",TraceClass([(UINavigationController *)current topViewController])];
        [names addObject:name];
    }
    return names.count ? [names componentsJoinedByString:@" > "] : @"none";
}
static void TraceState(YTKACENativeMenuTrace *trace, NSString *stage) {
    UIViewController *native = trace.native;
    NSMutableArray *children = [NSMutableArray array];
    for (UIViewController *child in native.childViewControllers) {
        if (children.count == 8) break;
        [children addObject:[child isKindOfClass:UINavigationController.class]
            ? [NSString stringWithFormat:@"%@(%@)",TraceClass(child),TraceClass([(UINavigationController *)child topViewController])]
            : TraceClass(child)];
    }
    id actions = Value(trace.owner,@"actions");
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] trace=%lu stage=%{public}@ elapsed=%.3f native=%{public}@ presenting=%{public}@ presented=%{public}@ dismissing=%d inWindow=%d alpha=%.2f children=%{public}@ ownerActions=%ld handlerReturned=%d selectorCalls=%lu uiActionCalls=%lu presentationRequests=%lu elmCalls=%lu controlParent=%{public}@ controlEnabled=%d controlInteraction=%d rootChain=%{public}@",
        (unsigned long)trace.identifier,stage,NSProcessInfo.processInfo.systemUptime - trace.start,
        TraceClass(native),TraceClass(native.presentingViewController),TraceClass(native.presentedViewController),native.isBeingDismissed,
        native.isViewLoaded && native.view.window != nil,native.isViewLoaded ? native.view.alpha : -1,
        [children componentsJoinedByString:@","],(long)([actions isKindOfClass:NSArray.class] ? [actions count] : -1),
        trace.handlerReturned,(unsigned long)trace.selectorCalls,(unsigned long)trace.uiActionCalls,
        (unsigned long)trace.presentationRequests,(unsigned long)trace.elmCalls,TraceClass(trace.control.superview),trace.control.enabled,
        trace.control.userInteractionEnabled,TraceControllerChain(trace.window));
}
static YTKACENativeMenuTrace *CurrentTrace(void) {
    if (ActiveTrace) return ActiveTrace;
    YTKACENativeMenuTrace *trace = RecentTrace;
    return trace && NSProcessInfo.processInfo.systemUptime - trace.start <= 3 ? trace : nil;
}
void YTKACETraceNativeControlDispatch(UIControl *control, NSString *phase,
    NSString *kind, SEL selector, id target, BOOL hasEvent) {
    if (!NSThread.isMainThread) return;
    YTKACENativeMenuTrace *trace = CurrentTrace();
    if (!trace || control != trace.control) return;
    if ([phase isEqual:@"enter"]) {
        if ([kind isEqual:@"selector"]) trace.selectorCalls++;
        else trace.uiActionCalls++;
    }
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] trace=%lu stage=dispatch phase=%{public}@ kind=%{public}@ control=%{public}@ target=%{public}@ selector=%{public}@ hasUIEvent=%d",
        (unsigned long)trace.identifier,phase,kind,TraceClass(control),TraceClass(target),
        selector ? NSStringFromSelector(selector) : @"none",hasEvent);
}
void YTKACETraceNativePresentation(UIViewController *presenter, UIViewController *presented) {
    if (!NSThread.isMainThread) return;
    YTKACENativeMenuTrace *trace = CurrentTrace();
    if (!trace || presenter.viewIfLoaded.window != trace.window || !trace.window) return;
    trace.presentationRequests++;
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] trace=%lu stage=present-request elapsed=%.3f duringHandler=%d presenter=%{public}@ controller=%{public}@ occupiedBy=%{public}@ dismissing=%d",
        (unsigned long)trace.identifier,NSProcessInfo.processInfo.systemUptime - trace.start,ActiveTrace == trace,
        TraceClass(presenter),TraceClass(presented),TraceClass(presenter.presentedViewController),presenter.isBeingDismissed);
}
static NSDictionary *TraceMetadata(id model, id button, NSUInteger index, NSString *route) {
    YTKACENativeMenuOwner *modelBox = [YTKACENativeMenuOwner new]; modelBox.value = model;
    YTKACENativeMenuOwner *buttonBox = [YTKACENativeMenuOwner new]; buttonBox.value = button;
    return @{@"model":modelBox,@"button":buttonBox,@"index":@(index),@"route":route};
}
static YTKACENativeMenuTrace *BeginTrace(UIViewController *native, NSDictionary *metadata) {
    YTKACENativeMenuTrace *trace = [YTKACENativeMenuTrace new];
    trace.identifier = ++TraceSequence; trace.start = NSProcessInfo.processInfo.systemUptime;
    trace.native = native; trace.window = native.viewIfLoaded.window;
    trace.owner = [(YTKACENativeMenuOwner *)objc_getAssociatedObject(native,NativeOwnerKey) value];
    id model = [(YTKACENativeMenuOwner *)metadata[@"model"] value];
    id button = [(YTKACENativeMenuOwner *)metadata[@"button"] value];
    if ([button isKindOfClass:UIControl.class]) trace.control = button;
    NSString *identifier = objc_getAssociatedObject(model,NativeItemIdentifierKey);
    if (![identifier hasPrefix:@"menu_item_"] || identifier.length > 128) identifier = @"unknown";
    id handler = Value(model,@"handler");
    NSMethodSignature *signature = HandlerSignature(handler);
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] trace=%lu stage=selection nativeIndex=%lu item=%{public}@ route=%{public}@ model=%{public}@ button=%{public}@ owner=%{public}@ handlerClass=%{public}@ handlerArgs=%ld handlerReturn=%{public}@ verifiedRoute=%d shouldDismissKnown=%d shouldDismiss=%d events=%lu enabled=%d interaction=%d tracking=%d touchInside=%d",
        (unsigned long)trace.identifier,(unsigned long)[metadata[@"index"] unsignedIntegerValue],identifier,metadata[@"route"] ?: @"unknown",
        TraceClass(model),TraceClass(button),TraceClass(trace.owner),TraceClass(handler),
        (long)(signature ? signature.numberOfArguments : -1),signature ? [NSString stringWithUTF8String:signature.methodReturnType] : @"unknown",
        objc_getAssociatedObject(model,NativeRouteKey) != nil,[model respondsToSelector:NSSelectorFromString(@"shouldDismissOnAction")],
        Flag(model,@"shouldDismissOnAction",YES),(unsigned long)trace.control.allControlEvents,
        trace.control.enabled,trace.control.userInteractionEnabled,trace.control.tracking,trace.control.touchInside);
    __block NSUInteger bindings = 0;
    [trace.control enumerateEventHandlers:^(UIAction *action, id target, SEL selector, UIControlEvents events, BOOL *stop) {
        if (bindings++ >= 24) { *stop = YES; return; }
        os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] trace=%lu stage=binding kind=%{public}@ events=%lu target=%{public}@ selector=%{public}@",
            (unsigned long)trace.identifier,action ? @"UIAction" : @"selector",(unsigned long)events,
            action ? TraceClass(action) : (target ? TraceClass(target) : @"responder-chain"),selector ? NSStringFromSelector(selector) : @"none");
    }];
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] trace=%lu stage=binding-summary count=%lu capped=%d",
        (unsigned long)trace.identifier,(unsigned long)MIN(bindings,24u),bindings > 24);
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    if ([button isKindOfClass:UIView.class]) [views addObject:button];
    NSUInteger gestures = 0;
    for (NSUInteger index = 0; index < views.count && index < 32; index++) {
        UIView *view = views[index];
        for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
            if (gestures++ >= 16) break;
            os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] trace=%lu stage=gesture view=%{public}@ class=%{public}@ delegate=%{public}@ enabled=%d state=%ld",
                (unsigned long)trace.identifier,TraceClass(view),TraceClass(gesture),TraceClass(gesture.delegate),gesture.enabled,(long)gesture.state);
        }
        for (UIView *child in view.subviews) if (views.count < 32) [views addObject:child];
    }
    RecentTrace = trace;
    TraceState(trace,@"selected-before-native-action");
    for (NSNumber *delay in @[@0.25,@1.0,@2.0]) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
        (int64_t)(delay.doubleValue * NSEC_PER_SEC)),dispatch_get_main_queue(),^{ TraceState(trace,@"settled"); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3 * NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if (RecentTrace == trace) RecentTrace = nil;
    });
    return trace;
}
static void RunTracedAction(YTKACENativeMenuTrace *trace, dispatch_block_t action) {
    YTKACENativeMenuTrace *previous = ActiveTrace; ActiveTrace = trace;
    TraceState(trace,@"handler-enter");
    BOOL returned = NO;
    @try { action(); returned = YES; trace.handlerReturned = YES; }
    @finally { TraceState(trace,returned ? @"handler-return" : @"handler-exception"); ActiveTrace = previous; }
}

static void InvokeELMTap(id command) {
    YTKACENativeMenuTrace *trace = CurrentTrace();
    trace.elmCalls++;
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] trace=%lu stage=elm-tap phase=enter target=%{public}@ selector=handleTap",
        (unsigned long)trace.identifier,TraceClass(command));
    BOOL returned = NO;
    @try { ((void (*)(id,SEL))objc_msgSend)(command,NSSelectorFromString(@"handleTap")); returned = YES; }
    @finally {
        os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] trace=%lu stage=elm-tap phase=%{public}@ target=%{public}@",
            (unsigned long)trace.identifier,returned ? @"return" : @"exception",TraceClass(command));
    }
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
        if (identifier) objc_setAssociatedObject(actions[index],NativeItemIdentifierKey,identifier,OBJC_ASSOCIATION_COPY_NONATOMIC);
        if (!objc_getAssociatedObject(actions[index],NativePresentationKey)[@"title"]) {
            NSString *title = Nonempty(Text(Value(renderers[index],@"menuNavigationItemRenderer"),@"text"))
                ?: Nonempty(Text(Value(renderers[index],@"menuServiceItemRenderer"),@"text"));
            if (title) {
                Capture(actions[index],title,nil,nil,nil,nil,nil);
                NSMutableDictionary *metadata = [objc_getAssociatedObject(actions[index],NativePresentationKey) mutableCopy];
                metadata[@"textSource"] = @"renderer";
                objc_setAssociatedObject(actions[index],NativePresentationKey,metadata,OBJC_ASSOCIATION_COPY_NONATOMIC);
            }
        }
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
    YTKACEInstallInstanceHook(@"YTActionSheetAction",@"setButton:",(IMP)SetButton,&OriginalSetButton);
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

static NSArray<NSDictionary *> *NativePlayerActions(UIViewController *controller, BOOL nativeViewsOnly, BOOL settled = YES) {
    // These links are used by YouTube's default/action/contextual sheet models.
    // Inspect a bounded controller/model graph, never infer actions from labels
    // or replay taps into the old clipped screen coordinates.
    objc_setAssociatedObject(controller,NativeTextRetryKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller,NativeRowsPendingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [controller loadViewIfNeeded];
    if (nativeViewsOnly) { [controller.view setNeedsLayout]; [controller.view layoutIfNeeded]; }
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
    NSUInteger spacers = 0, collapsed = 0;
    for (NSUInteger nativeIndex = 0; nativeIndex < models.count; ++nativeIndex) {
        id model = models[nativeIndex];
        id button = Value(model,@"button");
        NSDictionary *captured = objc_getAssociatedObject(model,NativePresentationKey);
        dispatch_block_t handler = ActionHandler(model);
        BOOL unsupportedELM = NO;
        id command = nativeViewsOnly ? ELMTapCommand(button,&unsupportedELM) : nil;
        dispatch_block_t activation = nil;
        if (command) activation = [^{ InvokeELMTap(command); } copy];
        else if (nativeViewsOnly) activation = ControlActivation(button);
        // A non-dismissing action navigates within the native sheet. Its owner
        // must still be presented when its original handler executes.
        BOOL retainsNative = nativeViewsOnly &&
            (activation != nil || !Flag(model,@"shouldDismissOnAction",YES));
        if (activation) handler = activation;
        NSDictionary *diagnostics = TraceMetadata(model,button,nativeIndex,
            command ? @"elm-command" : (activation ? @"control-event" : (objc_getAssociatedObject(model,NativeRouteKey) ? @"verified-route" : @"model-handler")));
        Class spacerClass = NSClassFromString(@"YTSpacerButton");
        if (nativeViewsOnly) {
            if (spacerClass && [button isKindOfClass:spacerClass] && !handler &&
                !Nonempty(PlainString(captured[@"title"])) && !Nonempty(Text(button,@"currentTitle")) &&
                !Nonempty(Text(button,@"currentAttributedTitle")) && !Nonempty(Text(button,@"accessibilityLabel"))) { spacers++; continue; }
            // Native action arrays include collapsed ELM rows (the device log
            // reports index 3 at 398 x -0). Give asynchronous ELM layout time
            // to materialize first. A row still at zero height after that is
            // absent from the native UI; do not invent a blank 44-point action
            // or reject all of its visible siblings.
            if ([button isKindOfClass:UIControl.class] && [button isDescendantOfView:controller.view] &&
                isfinite([button bounds].size.width) && [button bounds].size.width >= 44 &&
                isfinite([button bounds].size.height) && [button bounds].size.height >= 0 &&
                [button bounds].size.height < 24) {
                if (!settled) {
                    objc_setAssociatedObject(controller,NativeRowsPendingKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    return nil;
                }
                // ELM also emits short (e.g. 9pt) structural rows with a dummy
                // model handler. Never discard a short row with a real command.
                BOOL spacing = !command && !unsupportedELM &&
                    [button isKindOfClass:NSClassFromString(@"YTMenuItemElementsMDCButton")];
                if (spacing && [button bounds].size.height > 0) {
                    NSString *shortTitleSource = nil;
                    spacing = !Nonempty(ActionTitle(model,button,&shortTitleSource));
                    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithArray:[button subviews]];
                    for (NSUInteger i = 0; spacing && i < views.count && i < 64; i++) {
                        UIView *view = views[i];
                        if ([view isKindOfClass:UISwitch.class] ||
                            ([view isKindOfClass:UIControl.class] && [(UIControl *)view allControlEvents])) spacing = NO;
                        for (UIView *child in view.subviews) {
                            if (views.count >= 64) { spacing = NO; break; }
                            [views addObject:child];
                        }
                    }
                }
                if ([button bounds].size.height == 0 || spacing) {
                    collapsed++;
                    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] gear collapsed-row index=%lu class=%{public}@ bounds=%{public}@",
                        (unsigned long)nativeIndex,NSStringFromClass([button class]),NSStringFromCGRect([button bounds]));
                    continue;
                }
            }
            if (unsupportedELM) {
                os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] gear fallback reason=unsupported-or-ambiguous-elm-command index=%lu",(unsigned long)nativeIndex);
                return nil;
            }
            BOOL enabled = Flag(model,@"isEnabled",Flag(button,@"isEnabled",YES));
            YTKACEMenuNativeRow *row = [button isKindOfClass:UIControl.class] &&
                [button isDescendantOfView:controller.view] ? [[YTKACEMenuNativeRow alloc] initWithView:button] : nil;
            if (!row || (enabled && !handler)) {
                // Third-party actions appended to the native model array can
                // have a captured title/handler and no native button at all.
                // Let those use the shared metadata row below, alongside the
                // live ELM rows, rather than rejecting the complete gear menu.
                NSString *metadataSource = nil;
                if ((enabled && !handler) || !Nonempty(ActionTitle(model,button,&metadataSource))) {
                    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] gear row-unavailable index=%lu class=%{public}@ handler=%d bounds=%{public}@ parent=%{public}@ modelClass=%{public}@ elmCommand=%d",
                        (unsigned long)nativeIndex,button ? NSStringFromClass([button class]) : @"none",handler != nil,
                        [button isKindOfClass:UIView.class] ? NSStringFromCGRect([button bounds]) : @"none",
                        [button isKindOfClass:UIView.class] ? NSStringFromClass([[button superview] class]) : @"none",NSStringFromClass([model class]),command != nil);
                    return nil;
                }
                os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] gear metadata-row index=%lu modelClass=%{public}@ buttonClass=%{public}@",
                    (unsigned long)nativeIndex,NSStringFromClass([model class]),button ? NSStringFromClass([button class]) : @"none");
            } else {
                NSMutableDictionary *item = [@{@"nativeRow":row,@"enabled":@(enabled)} mutableCopy];
                NSString *identifier = objc_getAssociatedObject(model,NativeItemIdentifierKey);
                if ([identifier isEqual:@"menu_item_video_quality"]) item[@"qualityEntry"] = @YES;
                NSString *selectionTitle = Nonempty(PlainString(captured[@"title"])) ?: Nonempty(Text(button,@"currentTitle"))
                    ?: Nonempty(Text(Value(button,@"titleLabel"),@"text"));
                if (selectionTitle) item[@"selectionTitle"] = selectionTitle;
                if (handler) item[@"handler"] = handler;
                if (retainsNative) item[@"nativeActivation"] = @YES;
                item[@"nativeDiagnostics"] = diagnostics;
                item[@"refreshELMAtSelection"] = @YES;
                if (command) item[@"elmDismissAfterCommand"] = @(Flag(model,@"shouldDismissOnAction",YES));
                [actions addObject:item];
                continue;
            }
        }
        if (spacerClass && [button isKindOfClass:spacerClass] && !handler &&
            !Nonempty(Text(model,@"title")) && !Nonempty(Text(model,@"attributedTitle")) &&
            !Nonempty(Text(model,@"titleText")) && !Nonempty(Text(model,@"titleString")) && !captured[@"title"] &&
            !Nonempty(Text(button,@"currentTitle")) && !Nonempty(Text(button,@"currentAttributedTitle")) &&
            !Nonempty(Text(Value(button,@"titleLabel"),@"text")) && !Nonempty(Text(button,@"accessibilityLabel"))) {
            spacers++;
            continue;
        }
        NSString *titleSource = nil;
        NSString *title = ActionTitle(model,button,&titleSource);
        BOOL enabled = Flag(model,@"isEnabled",Flag(button,@"isEnabled",YES));
        YTKACEMenuNativeRow *nativeRow = nil;
        Class elementsButton = NSClassFromString(@"YTMenuItemElementsMDCButton");
        // The reported ELM row has callable behavior and rendered content, but
        // no text in either its node/controller graph or accessibility data.
        // Borrow the actual row after native layout instead of rejecting every
        // choice or inventing a title. VoiceOver keeps the native sheet when
        // text cannot be recovered; never replace it with an unnamed AX cell.
        if (!title.length && (!enabled || handler) && !UIAccessibilityIsVoiceOverRunning() &&
            elementsButton && [button isKindOfClass:elementsButton] &&
            [button isKindOfClass:UIView.class] && controller.presentingViewController &&
            [button window] == controller.view.window && [button isDescendantOfView:controller.view]) {
            nativeRow = [[YTKACEMenuNativeRow alloc] initWithView:button];
            if (nativeRow) {
                titleSource = @"native-view";
                os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] preserved native row index=%lu height=%.0f",
                    (unsigned long)nativeIndex,nativeRow.height);
            }
        }
        if ((!title.length && !nativeRow) || (enabled && !handler)) {
            BOOL retryText = !title.length && (!enabled || handler);
            objc_setAssociatedObject(controller,NativeTextRetryKey,@(retryText),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSString *identifier = objc_getAssociatedObject(model,NativeItemIdentifierKey);
            if (![identifier hasPrefix:@"menu_item_"] || identifier.length > 128) identifier = @"unknown";
            os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] %{public}@ reason=incomplete-action index=%lu class=%{public}@ title=%d handler=%d buttonClass=%{public}@ item=%{public}@ probe=%{public}@",
                retryText ? @"decode-deferred" : @"native fallback",(unsigned long)nativeIndex,
                NSStringFromClass([model class]),title.length != 0,handler != nil,
                button ? NSStringFromClass([button class]) : @"none",identifier,
                objc_getAssociatedObject(model,NativeTextProbeKey) ?: @{});
            return nil;
        }
        NSMutableDictionary *action = [@{@"enabled":@(enabled),
            @"selected":@(Flag(model,@"visiblySelected",captured[@"selected"] ? [captured[@"selected"] boolValue] : Flag(button,@"isSelected",NO)))} mutableCopy];
        if (nativeViewsOnly && [objc_getAssociatedObject(model,NativeItemIdentifierKey) isEqual:@"menu_item_video_quality"])
            action[@"qualityEntry"] = @YES;
        if (title.length) action[@"title"] = title;
        if (nativeRow) action[@"nativeRow"] = nativeRow;
        titleSources[titleSource] = @(titleSources[titleSource].unsignedIntegerValue + 1);
        if (handler) action[@"handler"] = handler;
        if (retainsNative) action[@"nativeActivation"] = @YES;
        action[@"nativeDiagnostics"] = diagnostics;
        if (nativeViewsOnly) action[@"refreshELMAtSelection"] = @YES;
        if (command) action[@"elmDismissAfterCommand"] = @(Flag(model,@"shouldDismissOnAction",YES));
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
    if (!actions.count) return nil;
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] decoded actions=%lu spacers=%lu collapsed=%lu titleSources=%{public}@",
        (unsigned long)actions.count,(unsigned long)spacers,(unsigned long)collapsed,titleSources);
    return actions;
}
NSArray<NSDictionary *> *YTKACENativePlayerActions(UIViewController *controller) { return NativePlayerActions(controller,NO); }
NSArray<NSDictionary *> *YTKACENativePlayerRows(UIViewController *controller) { return NativePlayerActions(controller,YES); }

static void PresentGearAfterLayout(UIViewController *controller, UIView *source, CGFloat alpha, NSUInteger attempt) {
    if (!controller.presentingViewController || controller.isBeingDismissed || controller.presentedViewController ||
        !YTKACEIsPlayerMenuSource(source)) { controller.view.alpha = alpha; return; }
    controller.view.alpha = alpha;
    NSArray *rows = NativePlayerActions(controller,YES,attempt >= 3);
    if (rows) {
        os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] gear layout-ready attempts=%lu",(unsigned long)attempt + 1);
        YTKACEPresentAdaptedPlayerMenu(controller,source,rows);
        return;
    }
    if ([objc_getAssociatedObject(controller,NativeRowsPendingKey) boolValue] && attempt < 3) {
        controller.view.alpha = 0;
        if (!attempt) os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] gear layout-pending reason=short-native-row");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50 * NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            PresentGearAfterLayout(controller,source,alpha,attempt + 1);
        });
        return;
    }
    YTKACEEnableNativeMenuOutsideDismissal(controller);
    YTKACECancelSystemMenuTransition(source);
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] gear fallback reason=unavailable-native-rows class=%{public}@ bounds=%{public}@",
        NSStringFromClass(controller.class),NSStringFromCGRect(controller.view.bounds));
}
void YTKACEPresentNativeGearMenu(UIViewController *controller, UIView *source) {
    PresentGearAfterLayout(controller,source,controller.view.alpha,0);
}

BOOL YTKACENativeMenuNeedsTextRetry(UIViewController *controller) {
    return [objc_getAssociatedObject(controller,NativeTextRetryKey) boolValue];
}

static void DismissNativeMenu(UIViewController *native, dispatch_block_t completion) {
    YTKACENativeMenuOwner *box = objc_getAssociatedObject(native,NativeOwnerKey);
    id owner = box.value;
    SEL dismiss = @selector(dismissViewControllerAnimated:completion:);
    NSMethodSignature *signature = [owner methodSignatureForSelector:dismiss];
    BOOL nativeOwner = owner && ![owner isKindOfClass:UIViewController.class] &&
        signature.numberOfArguments == 4 && signature.methodReturnType[0] == 'v' &&
        strchr("Bc",[signature getArgumentTypeAtIndex:2][0]) &&
        [signature getArgumentTypeAtIndex:3][0] == '@';
    if (native.presentingViewController && !native.isBeingDismissed && nativeOwner)
        ((void (*)(id,SEL,BOOL,id))objc_msgSend)(owner,dismiss,NO,completion);
    else if (native.presentingViewController && !native.isBeingDismissed)
        [native dismissViewControllerAnimated:NO completion:completion];
    else if (completion) completion();
}

@interface YTKACEELMPresentationRequest : NSObject
@property(nonatomic, strong) UIViewController *presenter, *controller;
@property(nonatomic) BOOL animated;
@property(nonatomic, copy) dispatch_block_t completion;
@end
@implementation YTKACEELMPresentationRequest @end
@interface YTKACEELMNavigation : NSObject
@property(nonatomic, strong) UIViewController *native, *presenter;
@property(nonatomic, strong) id owner;
@property(nonatomic, weak) UIView *source;
@property(nonatomic, copy) dispatch_block_t command;
@property(nonatomic, strong) NSMutableArray<YTKACEELMPresentationRequest *> *requests;
@property(nonatomic) BOOL shouldDismiss, finished;
@end
@implementation YTKACEELMNavigation @end
static YTKACEELMNavigation *ActiveELMNavigation, *ClosingELMNavigation;
static BOOL ControllerWithin(UIViewController *controller, UIViewController *ancestor) {
    if (!ancestor) return NO;
    for (NSUInteger depth = 0; controller && depth < 16; depth++, controller = controller.parentViewController)
        if (controller == ancestor) return YES;
    return NO;
}
BOOL YTKACEDeferNativeELMPresentation(UIViewController *presenter, UIViewController *presented,
    BOOL animated, dispatch_block_t completion) {
    if (!NSThread.isMainThread) return NO;
    YTKACEELMNavigation *navigation = ActiveELMNavigation ?: ClosingELMNavigation;
    if (!navigation || navigation.finished || presented.presentingViewController ||
        !(ControllerWithin(presenter,navigation.native) || ControllerWithin(presenter,navigation.presenter) ||
          ControllerWithin(navigation.presenter,presenter))) return NO;
    // A self-dismissing command may reach its own completion before our close
    // observer runs. Keep its anchor fresh and let a stable presenter proceed.
    if (!navigation.native.presentingViewController && !ControllerWithin(presenter,navigation.native)) {
        YTKACERememberPlayerMenuSource(navigation.source); return NO;
    }
    YTKACEELMPresentationRequest *request = [YTKACEELMPresentationRequest new];
    request.presenter = presenter; request.controller = presented;
    request.animated = animated; request.completion = completion;
    [navigation.requests addObject:request];
    YTKACEContinueSystemMenuTransition(navigation.source);
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] elm present-deferred presenter=%{public}@ controller=%{public}@ closeSource=%d",
        TraceClass(presenter),TraceClass(presented),navigation.shouldDismiss);
    return YES;
}
static void ReplayELMPresentations(YTKACEELMNavigation *navigation) {
    if (navigation.finished) return;
    navigation.finished = YES;
    if (ClosingELMNavigation == navigation) ClosingELMNavigation = nil;
    NSArray<YTKACEELMPresentationRequest *> *requests = navigation.requests.copy;
    [navigation.requests removeAllObjects];
    for (YTKACEELMPresentationRequest *request in requests) {
        UIViewController *presenter = request.presenter;
        if (!navigation.shouldDismiss) presenter = navigation.native;
        else if (ControllerWithin(presenter,navigation.native)) presenter = navigation.presenter;
        if (!presenter.viewIfLoaded.window || presenter.isBeingDismissed || presenter.presentedViewController) {
            os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] elm replay-blocked presenter=%{public}@ occupiedBy=%{public}@",
                TraceClass(presenter),TraceClass(presenter.presentedViewController));
            continue;
        }
        YTKACERememberPlayerMenuSource(navigation.source);
        os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] elm present-replay controller=%{public}@ closeSource=%d sourceStillPresented=%d",
            TraceClass(request.controller),navigation.shouldDismiss,navigation.native.presentingViewController != nil);
        [presenter presentViewController:request.controller animated:request.animated completion:^{
            // Keep the ELM command, its owner and node graph alive through presentation.
            os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] elm presentation-completed owner=%{public}@",TraceClass(navigation.owner));
            if (request.completion) request.completion();
        }];
    }
}
static void AwaitELMDismissal(YTKACEELMNavigation *navigation, NSUInteger attempt) {
    if (navigation.finished) return;
    if (!navigation.native.presentingViewController && !navigation.native.isBeingDismissed) {
        ReplayELMPresentations(navigation); return;
    }
    if (attempt >= 60) {
        os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] elm replay-stopped reason=native-dismissal-incomplete");
        navigation.finished = YES; [navigation.requests removeAllObjects];
        if (ClosingELMNavigation == navigation) ClosingELMNavigation = nil;
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50 * NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        AwaitELMDismissal(navigation,attempt + 1);
    });
}
static void CompleteELMNavigation(YTKACEELMNavigation *navigation) {
    UIViewController *native = navigation.native;
    if (!navigation.shouldDismiss) { ReplayELMPresentations(navigation); return; }
    // A command that has already presented its own child retains native control
    // of that hierarchy. Never dismiss an entire newly opened child stack.
    if (native.presentedViewController) {
        os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] elm close-skipped reason=native-child-presented");
        ReplayELMPresentations(navigation); return;
    }
    ClosingELMNavigation = navigation;
    if (native.isBeingDismissed || !native.presentingViewController) {
        os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] elm close-skipped reason=command-already-dismissed");
        AwaitELMDismissal(navigation,0);
    } else {
        os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] elm close-after-command owner=%{public}@",TraceClass(navigation.owner));
        DismissNativeMenu(native,^{ AwaitELMDismissal(navigation,0); });
    }
}

// Only native fallbacks opened from a verified player button receive this
// recognizer. Locate the actual panel on every touch so rotation/dragging cannot
// turn a stale frame into an outside hit. Unknown layouts keep native behavior.
static UIView *NativePanel(UIViewController *controller) {
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:controller.view];
    NSArray *names = @[@"YTDraggableView",@"YTContextualWrapView",@"YTMinimumWidthDialogView",@"GOODialogView"];
    for (NSUInteger index = 0; index < queue.count && index < 256; ++index) {
        UIView *view = queue[index];
        if (view.hidden || view.alpha < 0.05) continue;
        for (NSString *name in names) {
            Class cls = NSClassFromString(name);
            if (cls && [view isKindOfClass:cls] &&
                !CGRectIsEmpty(view.bounds)) return view;
        }
        for (UIView *child in view.subviews) {
            if (queue.count >= 256) break;
            [queue addObject:child];
        }
    }
    return nil;
}

@interface YTKACENativeOutsideTap : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, weak) UIViewController *native;
@property(nonatomic, strong) UITapGestureRecognizer *gesture;
@end
@implementation YTKACENativeOutsideTap
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    UIViewController *native = self.native;
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Interface.SystemMenus") ||
        !native.presentingViewController || native.isBeingDismissed || native.presentedViewController ||
        native.view.hidden || native.view.alpha < 0.05) return NO;
    UIView *panel = NativePanel(native);
    if (!panel || panel.window != gesture.view.window || !gesture.view.window) return NO;
    return CGRectContainsPoint(gesture.view.bounds,[touch locationInView:gesture.view]) &&
        !CGRectContainsPoint(panel.bounds,[touch locationInView:panel]);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    (void)gesture; (void)other; return YES;
}
- (void)close:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    UIViewController *native = self.native;
    if (!native.presentingViewController || native.isBeingDismissed || native.presentedViewController) return;
    [gesture.view removeGestureRecognizer:gesture];
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] native fallback close=outside-tap");
    DismissNativeMenu(native,nil);
}
@end

void YTKACEEnableNativeMenuOutsideDismissal(UIViewController *controller) {
    UIView *container = controller.presentationController.containerView;
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Interface.SystemMenus") ||
        !container || !controller.presentingViewController) return;
    YTKACENativeOutsideTap *previous = objc_getAssociatedObject(controller,NativeOutsideTapKey);
    [previous.gesture.view removeGestureRecognizer:previous.gesture];
    YTKACENativeOutsideTap *outside = [YTKACENativeOutsideTap new]; outside.native = controller;
    outside.gesture = [[UITapGestureRecognizer alloc] initWithTarget:outside action:@selector(close:)];
    outside.gesture.delegate = outside;
    outside.gesture.cancelsTouchesInView = NO;
    [container addGestureRecognizer:outside.gesture];
    objc_setAssociatedObject(controller,NativeOutsideTapKey,outside,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *panel = NativePanel(controller);
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] native fallback outside-tap panel=%{public}@",
        panel ? NSStringFromClass(panel.class) : @"unresolved");
}

@interface YTKACENativeMenuSession : NSObject
@property(nonatomic, weak) UIViewController *native;
@property(nonatomic, weak) UIView *source;
@property(nonatomic) CGFloat originalAlpha;
@property(nonatomic, copy) NSArray<UIView *> *backdrops;
@property(nonatomic, copy) NSArray<NSNumber *> *backdropAlphas;
@property(nonatomic) BOOL finished;
@property(nonatomic, copy) NSArray<YTKACEMenuNativeRow *> *nativeRows;
- (void)finish:(dispatch_block_t)action;
- (void)activateNative:(dispatch_block_t)action;
- (void)activateELM:(dispatch_block_t)action shouldDismiss:(BOOL)shouldDismiss;
- (void)returnToNative;
@end
@implementation YTKACENativeMenuSession
- (void)restore {
    for (YTKACEMenuNativeRow *row in self.nativeRows) [row restore];
    self.native.view.alpha = self.originalAlpha;
    [self.backdrops enumerateObjectsUsingBlock:^(UIView *view, NSUInteger index, BOOL *stop) {
        (void)stop; view.alpha = self.backdropAlphas[index].doubleValue;
    }];
    self.backdrops = nil; self.backdropAlphas = nil;
}
- (void)returnToNative {
    if (self.finished) return;
    self.finished = YES; [self restore];
    YTKACEEnableNativeMenuOutsideDismissal(self.native);
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] elm fallback reason=command-changed-before-selection");
}
- (void)activateELM:(dispatch_block_t)action shouldDismiss:(BOOL)shouldDismiss {
    if (self.finished) return;
    self.finished = YES;
    [self restore];
    YTKACEELMNavigation *navigation = [YTKACEELMNavigation new];
    navigation.native = self.native;
    navigation.presenter = self.native.presentingViewController;
    navigation.owner = [(YTKACENativeMenuOwner *)objc_getAssociatedObject(self.native,NativeOwnerKey) value];
    navigation.source = self.source; navigation.command = action;
    navigation.shouldDismiss = shouldDismiss; navigation.requests = [NSMutableArray array];
    YTKACERememberPlayerMenuSource(self.source);
    YTKACEELMNavigation *previous = ActiveELMNavigation;
    ActiveELMNavigation = navigation;
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] elm command-before-close shouldDismiss=%d",shouldDismiss);
    @try { action(); }
    @finally { ActiveELMNavigation = previous; }
    CompleteELMNavigation(navigation);
}
- (void)activateNative:(dispatch_block_t)action {
    if (self.finished) return;
    self.finished = YES;
    [self restore];
    UIViewController *native = self.native;
    YTKACENativeMenuOwner *box = objc_getAssociatedObject(native,NativeOwnerKey);
    // Keep the owner and its responders alive for synchronous native dispatch.
    __attribute__((objc_precise_lifetime)) id owner = box.value;
    (void)owner;
    YTKACERememberPlayerMenuSource(self.source);
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] adapted activation=native owner=%{public}@",
        owner ? NSStringFromClass([owner class]) : @"none");
    if (action) action();
}
- (void)finish:(dispatch_block_t)action {
    if (self.finished) return;
    self.finished = YES;
    // Restore borrowed controls before the native owner's dismissal lifecycle.
    for (YTKACEMenuNativeRow *row in self.nativeRows) [row restore];
    UIViewController *native = self.native;
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] adapted close selected=%d",action != nil);
    // Keep the real sheet's appearance, dismissal and transitioning delegate.
    // Its original presentation was never changed to a popover. Close it before
    // running an action which can synchronously present the next native page.
    YTKACENativeMenuOwner *box = objc_getAssociatedObject(native,NativeOwnerKey);
    id owner = box.value;
    void (^completion)(void) = ^{
        __attribute__((objc_precise_lifetime)) id retainedOwner = owner;
        (void)retainedOwner;
        [self restore];
        if (action) { YTKACERememberPlayerMenuSource(self.source); action(); }
    };
    // YTDefaultSheetController also owns state used by quality coordinators.
    DismissNativeMenu(native,completion);
}
@end

void YTKACEPresentAdaptedPlayerMenu(UIViewController *controller, UIView *source, NSArray<NSDictionary *> *actions) {
    YTKACENativeMenuSession *session = [YTKACENativeMenuSession new];
    session.native = controller;
    session.source = source;
    session.originalAlpha = controller.view.alpha;
    NSMutableArray *nativeRows = [NSMutableArray array];
    for (NSDictionary *item in actions) if (item[@"nativeRow"]) [nativeRows addObject:item[@"nativeRow"]];
    session.nativeRows = nativeRows;
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
        if (original) {
            __block YTKACENativeMenuTrace *trace = nil;
            __block id selectedCommand = nil;
            __block BOOL unsupportedELM = NO;
            dispatch_block_t prepare = ^{
                unsupportedELM = NO; selectedCommand = nil;
                NSMutableDictionary *metadata = [item[@"nativeDiagnostics"] mutableCopy];
                if ([item[@"refreshELMAtSelection"] boolValue]) {
                    id button = [(YTKACENativeMenuOwner *)metadata[@"button"] value];
                    selectedCommand = ELMTapCommand(button,&unsupportedELM);
                    if (item[@"elmDismissAfterCommand"] && !selectedCommand) unsupportedELM = YES;
                    if (selectedCommand) metadata[@"route"] = @"elm-command";
                    if (unsupportedELM) metadata[@"route"] = @"unsupported-elm-command";
                }
                trace = BeginTrace(session.native,metadata);
            };
            copy[@"diagnosticSelection"] = [prepare copy];
            copy[@"submenuTransition"] = [^BOOL { return selectedCommand != nil && !unsupportedELM; } copy];
            copy[@"handler"] = [^{
                if (!trace) prepare();
                if (unsupportedELM) { [session returnToNative]; return; }
                id command = selectedCommand;
                dispatch_block_t effective = original;
                if (command) effective = ^{ InvokeELMTap(command); };
                dispatch_block_t invocation = ^{ RunTracedAction(trace,effective); };
                if (command) {
                    NSDictionary *metadata = item[@"nativeDiagnostics"];
                    id model = [(YTKACENativeMenuOwner *)metadata[@"model"] value];
                    [session activateELM:invocation shouldDismiss:Flag(model,@"shouldDismissOnAction",YES)];
                } else if ([item[@"nativeActivation"] boolValue]) [session activateNative:invocation];
                else [session finish:invocation];
            } copy];
        }
        [adapted addObject:copy];
    }
    if (!YTKACEPresentSystemMenuWithDismissal(controller,source,controller.title,nil,adapted,^(BOOL selected) {
        if (!selected) [session finish:nil];
    })) {
        [session restore];
        YTKACEEnableNativeMenuOutsideDismissal(controller);
        os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] native fallback reason=anchor-or-presenter");
        return;
    }
    os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] adapted class=%{public}@ actions=%lu",
        NSStringFromClass(controller.class),(unsigned long)actions.count);
}
