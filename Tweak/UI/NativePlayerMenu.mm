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
                isfinite([button bounds].size.height) && [button bounds].size.height == 0) {
                if (!settled) {
                    objc_setAssociatedObject(controller,NativeRowsPendingKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    return nil;
                }
                collapsed++;
                os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] gear collapsed-row index=%lu class=%{public}@ bounds=%{public}@",
                    (unsigned long)nativeIndex,NSStringFromClass([button class]),NSStringFromCGRect([button bounds]));
                continue;
            }
            BOOL enabled = Flag(model,@"isEnabled",Flag(button,@"isEnabled",YES));
            YTKACEMenuNativeRow *row = [button isKindOfClass:UIControl.class] &&
                [button isDescendantOfView:controller.view] ? [[YTKACEMenuNativeRow alloc] initWithView:button] : nil;
            if (!row || (enabled && !handler)) {
                os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] gear row-unavailable index=%lu class=%{public}@ handler=%d bounds=%{public}@ parent=%{public}@",
                    (unsigned long)nativeIndex,button ? NSStringFromClass([button class]) : @"none",handler != nil,
                    [button isKindOfClass:UIView.class] ? NSStringFromCGRect([button bounds]) : @"none",
                    [button isKindOfClass:UIView.class] ? NSStringFromClass([[button superview] class]) : @"none");
                return nil;
            }
            NSMutableDictionary *item = [@{@"nativeRow":row,@"enabled":@(enabled)} mutableCopy];
            NSString *identifier = objc_getAssociatedObject(model,NativeItemIdentifierKey);
            if ([identifier isEqual:@"menu_item_video_quality"]) item[@"qualityEntry"] = @YES;
            NSString *selectionTitle = Nonempty(PlainString(captured[@"title"])) ?: Nonempty(Text(button,@"currentTitle"))
                ?: Nonempty(Text(Value(button,@"titleLabel"),@"text"));
            if (selectionTitle) item[@"selectionTitle"] = selectionTitle;
            if (handler) item[@"handler"] = handler;
            [actions addObject:item];
            continue;
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
        if (title.length) action[@"title"] = title;
        if (nativeRow) action[@"nativeRow"] = nativeRow;
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
        if (!attempt) os_log(OS_LOG_DEFAULT,"[YTKACE PlayerMenus] gear layout-pending reason=zero-height-row");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50 * NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            PresentGearAfterLayout(controller,source,alpha,attempt + 1);
        });
        return;
    }
    YTKACEEnableNativeMenuOutsideDismissal(controller);
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
    void (^completion)(void) = ^{
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
        if (original) copy[@"handler"] = [^{ [session finish:original]; } copy];
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
