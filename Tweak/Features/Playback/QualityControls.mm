// Quality shortcut inspired by PoomSmart/YouQuality (MIT, 2023–2026).
// The original license is included in YTKACE.bundle/Licenses/YouQuality.txt.
// Rendering, preferences and button lifetime are owned by YTKACE.
#import "QualityControls.h"
#import "../../YTKACE.h"
#import "../../UI/OverlayButtonHost.h"
#import "../../UI/Notice.h"
#import "../../UI/SystemMenu.h"
#import "../../UI/NativePlayerMenu.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import "../../Runtime/Localization.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>

static IMP OriginalQualitySelection, OriginalRedesignedQualitySelection, OriginalFormatConstraint;
static const void *SelectedQualityKey = &SelectedQualityKey;
static NSMapTable<UIView *,UIButton *> *QualityButtons;
static NSString * const QualityButtonKey = @"YTKACE.Preference.Playback.QualityButton";
static const void *OverlaySelectionKey = &OverlaySelectionKey;
static __weak UIView *SelectionOverlay, *SelectionSource;
static __weak id SelectionVideo;
static __weak id SelectionController;
static NSString *SelectionVideoID;
static BOOL SelectionIsQuality;
static BOOL SelectionHadVideo;
@interface YTKACEQualityLabelState : NSObject
@property(nonatomic, weak) id video;
@property(nonatomic, weak) id controller;
@property(nonatomic, copy) NSString *videoID;
@property(nonatomic, copy) NSString *label;
@property(nonatomic) BOOL selected;
@property(nonatomic) BOOL hadVideo;
@end
@implementation YTKACEQualityLabelState @end

NSString *YTKACEQualityButtonTitle(NSString *label) {
    if (![label isKindOfClass:NSString.class] || !label.length) return YTKACELocalized(@"Auto");
    if ([label hasPrefix:@"2160p"]) return @"4K";
    if ([label hasPrefix:@"1440p"]) return @"2K";
    NSRange p = [label rangeOfString:@"p"];
    if (p.location != NSNotFound) {
        NSString *digits = [label substringToIndex:p.location];
        if (digits.length && [digits rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound)
            return [label substringToIndex:NSMaxRange(p)];
    }
    return [label componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].firstObject;
}

static id QualityObject(id object, NSString *name) {
    if (!object) return nil;
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (signature.numberOfArguments == 2 && signature.methodReturnType[0] == '@')
        return ((id (*)(id, SEL))objc_msgSend)(object,selector);
    for (NSString *key in @[name,[@"_" stringByAppendingString:name]]) {
        Ivar ivar = class_getInstanceVariable([object class],key.UTF8String);
        if (ivar && ivar_getTypeEncoding(ivar)[0] == '@') return object_getIvar(object,ivar);
    }
    return nil;
}

// activeVideo is a YTSingleVideoController; selection callbacks can carry its
// YTSingleVideo model. Key both reads and writes to that same underlying object.
static id QualityVideo(id video) {
    return QualityObject(video,@"singleVideo") ?: QualityObject(video,@"videoData") ?: video;
}
static id OverlayVideoController(UIView *overlay) {
    return QualityObject(QualityObject(overlay,@"playerViewController"),@"activeVideo");
}
static id OverlayQualityVideo(UIView *overlay) {
    return QualityVideo(OverlayVideoController(overlay));
}
static NSString *QualityVideoID(id video) {
    id value = QualityObject(video,@"videoId");
    return [value isKindOfClass:NSString.class] ? value : nil;
}
static void BeginSelection(UIView *overlay, UIView *source, BOOL quality) {
    SelectionOverlay = overlay; SelectionSource = source; SelectionIsQuality = quality;
    SelectionVideo = OverlayQualityVideo(overlay); SelectionVideoID = [QualityVideoID(SelectionVideo) copy];
    SelectionController = OverlayVideoController(overlay);
    SelectionHadVideo = SelectionVideo != nil;
}
static BOOL CurrentSelection(UIView *overlay) {
    if (overlay != SelectionOverlay) return NO;
    id current = OverlayQualityVideo(overlay);
    NSString *identifier = QualityVideoID(current);
    if (identifier.length && SelectionVideoID.length && ![identifier isEqual:SelectionVideoID]) return NO;
    return current == SelectionVideo || (SelectionController && OverlayVideoController(overlay) == SelectionController) ||
        (!SelectionHadVideo && !SelectionVideoID.length) ||
        (identifier.length && [identifier isEqual:SelectionVideoID]);
}
static void StoreOverlaySelection(UIView *overlay, NSString *label) {
    YTKACEQualityLabelState *state = [YTKACEQualityLabelState new];
    state.video = OverlayQualityVideo(overlay); state.videoID = QualityVideoID(state.video);
    state.controller = OverlayVideoController(overlay);
    state.hadVideo = state.video != nil;
    state.label = label; state.selected = YES;
    objc_setAssociatedObject(overlay,OverlaySelectionKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void UpdateQualityButton(UIView *overlay, UIButton *button) {
    id video = OverlayQualityVideo(overlay);
    YTKACEQualityLabelState *state = objc_getAssociatedObject(overlay,OverlaySelectionKey);
    NSString *identifier = QualityVideoID(video);
    BOOL changedID = identifier.length && state.videoID.length && ![identifier isEqual:state.videoID];
    BOOL sameController = state.controller && OverlayVideoController(overlay) == state.controller;
    if (state.selected && (changedID || (video && state.hadVideo && video != state.video && !sameController &&
        !(state.videoID.length && [state.videoID isEqual:identifier])))) state.selected = NO;
    if (state.selected && video && !state.hadVideo) { state.video = video; state.videoID = QualityVideoID(video); state.hadVideo = YES; }
    NSString *label = state.selected ? state.label : (video ? objc_getAssociatedObject(video,SelectedQualityKey) : nil);
    NSString *title = YTKACEQualityButtonTitle(label);
    if (![button.currentTitle isEqual:title]) [button setTitle:title forState:UIControlStateNormal];
    button.accessibilityValue = label ?: YTKACELocalized(@"Auto");
}
static NSString *QualityChoice(NSString *label) {
    if (![label isKindOfClass:NSString.class]) return nil;
    NSScanner *scanner = [NSScanner scannerWithString:label]; NSInteger resolution = 0;
    BOOL format = [scanner scanInteger:&resolution] && resolution >= 144 && resolution <= 8640 && [scanner scanString:@"p" intoString:nil];
    BOOL automatic = NO;
    for (NSString *name in @[@"Auto",YTKACELocalized(@"Auto")]) {
        if (label.length < name.length || [[label substringToIndex:name.length] caseInsensitiveCompare:name] != NSOrderedSame) continue;
        if (label.length == name.length || [[NSCharacterSet characterSetWithCharactersInString:@" (（\n"] characterIsMember:[label characterAtIndex:name.length]]) automatic = YES;
    }
    if (automatic) return @"";
    return format || [label isEqual:@"4K"] || [label isEqual:@"2K"] ? label : nil;
}
static void ApplyChoice(UIView *overlay, NSString *choice, NSString *route) {
    if (!overlay || !choice) return;
    StoreOverlaySelection(overlay,choice.length ? choice : nil);
    UpdateQualityButton(overlay,[QualityButtons objectForKey:overlay]); [overlay setNeedsLayout];
    os_log(OS_LOG_DEFAULT,"[YTKACE Quality] selection source=%{public}@ labelPresent=%d",route,choice.length != 0);
}

static id QualityPresenter(UIView *overlay) {
    SEL action = NSSelectorFromString(@"didPressVideoQuality:");
    id events = QualityObject(overlay,@"eventsDelegate");
    if (!events) { @try { events = [overlay valueForKey:@"_eventsDelegate"]; } @catch (__unused NSException *exception) {} }
    if ([events respondsToSelector:action]) return events;
    id player = QualityObject(overlay,@"playerViewController");
    id controller = QualityObject(player,@"activeVideoPlayerOverlay");
    return [controller respondsToSelector:action] ? controller : nil;
}

@interface YTKACEQualityControls : NSObject
@property(nonatomic, weak) UIView *overlay;
@property(nonatomic, weak) UIButton *button;
+ (instancetype)shared;
- (void)openQuality:(UIButton *)sender;
@end
@implementation YTKACEQualityControls
+ (instancetype)shared {
    static YTKACEQualityControls *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ value = [self new]; });
    return value;
}
- (void)openQuality:(UIButton *)sender {
    BeginSelection(self.overlay,sender,YES);
    id presenter = QualityPresenter(self.overlay);
    UIViewController *controller = [presenter isKindOfClass:UIViewController.class] ? presenter : nil;
    os_log(OS_LOG_DEFAULT, "[YTKACE Quality] open presenter=%{public}@ presented=%{public}@ dismissing=%d sourceVisible=%d",
        presenter ? NSStringFromClass([presenter class]) : @"missing",
        controller.presentedViewController ? NSStringFromClass(controller.presentedViewController.class) : @"none",
        controller.isBeingDismissed, sender.window != nil && !sender.hidden);
    if (presenter) ((void (*)(id, SEL, id))objc_msgSend)(presenter,NSSelectorFromString(@"didPressVideoQuality:"),sender);
    else YTKACEShowNotice(YTKACELocalized(@"Open video quality from the player settings."));
}
@end

static void RememberQuality(id video, NSString *label, NSString *source) {
    dispatch_block_t update = ^{
        id identity = QualityVideo(video);
        if (identity) objc_setAssociatedObject(identity,SelectedQualityKey,label,OBJC_ASSOCIATION_COPY_NONATOMIC);
        NSUInteger matched = 0;
        for (UIView *overlay in QualityButtons.keyEnumerator.allObjects) {
            BOOL match = identity && OverlayQualityVideo(overlay) == identity;
            NSString *incomingID = QualityVideoID(identity), *currentID = QualityVideoID(OverlayQualityVideo(overlay));
            BOOL context = CurrentSelection(overlay) &&
                !(incomingID.length && currentID.length && ![incomingID isEqual:currentID]);
            if (!match && !context) continue;
            // Update immediately: the host can defer layout during native menu
            // transitions. A pending layout alone leaves the previous title up.
            StoreOverlaySelection(overlay,label);
            UpdateQualityButton(overlay,[QualityButtons objectForKey:overlay]);
            [overlay setNeedsLayout]; matched++;
        }
        os_log(OS_LOG_DEFAULT,"[YTKACE Quality] selection source=%{public}@ videoClass=%{public}@ identityClass=%{public}@ labelPresent=%d matchedOverlays=%lu",
            source,video ? NSStringFromClass([video class]) : @"none",
            identity ? NSStringFromClass([identity class]) : @"none",label.length != 0,(unsigned long)matched);
    };
    if (NSThread.isMainThread) update(); else dispatch_async(dispatch_get_main_queue(),update);
}
static void QualitySelection(id self, SEL cmd, id video, id format) {
    id value = QualityObject(format,@"qualityLabel");
    NSString *label = [value isKindOfClass:NSString.class] ? [value copy] : nil;
    id identity = QualityVideo(video);
    if (OriginalQualitySelection) ((void (*)(id,SEL,id,id))OriginalQualitySelection)(self,cmd,video,format);
    if (!format || label) RememberQuality(identity,label,@"original-selector");
    else os_log(OS_LOG_DEFAULT,"[YTKACE Quality] selection source=original-selector labelUnavailable=1 formatClass=%{public}@",NSStringFromClass([format class]));
}
static void RedesignedQualitySelection(id self, SEL cmd, id video, id format) {
    id value = QualityObject(format,@"qualityLabel");
    NSString *label = [value isKindOfClass:NSString.class] ? [value copy] : nil;
    id identity = QualityVideo(video);
    if (OriginalRedesignedQualitySelection) ((void (*)(id,SEL,id,id))OriginalRedesignedQualitySelection)(self,cmd,video,format);
    if (!format || label) RememberQuality(identity,label,@"redesigned-selector");
    else os_log(OS_LOG_DEFAULT,"[YTKACE Quality] selection source=redesigned-selector labelUnavailable=1 formatClass=%{public}@",NSStringFromClass([format class]));
}
static void FormatConstraint(id self, SEL cmd, id constraint) {
    id value = QualityObject(constraint,@"qualityLabel");
    NSString *label = [value isKindOfClass:NSString.class] ? [value copy] : nil;
    id identity = QualityVideo(self);
    if (OriginalFormatConstraint) ((void (*)(id,SEL,id))OriginalFormatConstraint)(self,cmd,constraint);
    // Modern native choices can apply the constraint directly. Only display an
    // actual native quality label, or clear a removed constraint (Auto).
    if (!constraint || label) RememberQuality(identity,label,@"format-constraint");
}

void YTKACEInstallQualityControls(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        QualityButtons = [NSMapTable weakToWeakObjectsMapTable];
        [NSNotificationCenter.defaultCenter addObserverForName:YTKACEPlayerMenuTouchSource object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                UIView *source = note.object;
                for (UIView *overlay in QualityButtons.keyEnumerator.allObjects)
                    if (source == overlay || [source isDescendantOfView:overlay]) {
                        BeginSelection(overlay,source,source == [QualityButtons objectForKey:overlay]);
                        return;
                    }
                if ([note.userInfo[@"activation"] boolValue] && SelectionIsQuality && CurrentSelection(SelectionOverlay)) {
                    NSString *title = YTKACENativeControlTitle(source) ?: QualityObject(source,@"currentTitle") ?:
                        QualityObject(QualityObject(source,@"titleLabel"),@"text");
                    NSString *choice = QualityChoice(title);
                    os_log(OS_LOG_DEFAULT,"[YTKACE Quality] native-control class=%{public}@ labelSupported=%d",NSStringFromClass(source.class),choice != nil);
                    ApplyChoice(SelectionOverlay,choice,@"native-control");
                }
            }];
        [NSNotificationCenter.defaultCenter addObserverForName:YTKACEPlayerMenuWillSelectAction object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                UIView *source = note.object, *overlay = nil;
                if ([note.userInfo[@"qualityEntry"] boolValue] && CurrentSelection(SelectionOverlay)) {
                    SelectionIsQuality = YES; SelectionSource = source; return;
                }
                for (UIView *candidate in QualityButtons.keyEnumerator.allObjects)
                    if ([QualityButtons objectForKey:candidate] == source) { overlay = candidate; break; }
                if (!overlay && SelectionIsQuality && source == SelectionSource && CurrentSelection(SelectionOverlay)) overlay = SelectionOverlay;
                if (!overlay) return;
                ApplyChoice(overlay,QualityChoice(note.userInfo[@"selectionTitle"] ?: note.userInfo[@"title"]) ?: QualityChoice(note.userInfo[@"value"]),@"menu-choice");
            }];
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSDictionary *stored = [defaults persistentDomainForName:NSBundle.mainBundle.bundleIdentifier ?: @""];
        id legacy = stored[@"YTVideoOverlay-YouQuality-Enabled"];
        if (!stored[QualityButtonKey] && legacy) [defaults setBool:[legacy boolValue] forKey:QualityButtonKey];
        [defaults registerDefaults:@{QualityButtonKey:@YES}];
        YTKACEInstallInstanceHook(@"YTVideoQualitySwitchOriginalController",@"singleVideo:didSelectVideoFormat:",
            (IMP)QualitySelection,&OriginalQualitySelection);
        YTKACEInstallInstanceHook(@"YTVideoQualitySwitchRedesignedController",@"singleVideo:didSelectVideoFormat:",
            (IMP)RedesignedQualitySelection,&OriginalRedesignedQualitySelection);
        YTKACEInstallInstanceHook(@"YTSingleVideoController",@"setVideoFormatConstraint:",
            (IMP)FormatConstraint,&OriginalFormatConstraint);
        YTKACERegisterOverlayConfigurator(@"quality", ^(UIView *overlay, UIStackView *stack) {
            YTKACEQualityControls *controls = YTKACEQualityControls.shared;
            controls.overlay = overlay;
            UIButton *button = YTKACEOverlayButton(stack,@"YTKACE Quality",@"gearshape",controls,@selector(openQuality:));
            controls.button = button;
            [QualityButtons setObject:button forKey:overlay];
            UpdateQualityButton(overlay,button);
            [button setImage:nil forState:UIControlStateNormal];
            button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
            button.titleLabel.numberOfLines = 1;
            button.titleLabel.adjustsFontSizeToFitWidth = YES;
            button.titleLabel.minimumScaleFactor = 0.7;
            button.titleLabel.lineBreakMode = NSLineBreakByClipping;
            button.contentEdgeInsets = UIEdgeInsetsZero;
            button.titleEdgeInsets = UIEdgeInsetsZero;
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            button.accessibilityLabel = YTKACELocalized(@"Video Quality");
            button.hidden = !YTKACEFeatureEnabled(QualityButtonKey);
        });
    });
}
