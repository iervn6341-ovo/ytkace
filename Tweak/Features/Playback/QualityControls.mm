// Quality shortcut inspired by PoomSmart/YouQuality (MIT, 2023–2026).
// The original license is included in YTKACE.bundle/Licenses/YouQuality.txt.
// Rendering, preferences and button lifetime are owned by YTKACE.
#import "QualityControls.h"
#import "../../YTKACE.h"
#import "../../UI/OverlayButtonHost.h"
#import "../../UI/Notice.h"
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
static id OverlayQualityVideo(UIView *overlay) {
    return QualityVideo(QualityObject(QualityObject(overlay,@"playerViewController"),@"activeVideo"));
}
static void UpdateQualityButton(UIView *overlay, UIButton *button) {
    id video = OverlayQualityVideo(overlay);
    NSString *label = video ? objc_getAssociatedObject(video,SelectedQualityKey) : nil;
    NSString *title = YTKACEQualityButtonTitle(label);
    if (![button.currentTitle isEqual:title]) [button setTitle:title forState:UIControlStateNormal];
    button.accessibilityValue = label ?: YTKACELocalized(@"Auto");
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

static void RememberQuality(id video, id format, NSString *source) {
    NSString *label = QualityObject(format,@"qualityLabel");
    if (![label isKindOfClass:NSString.class]) label = nil;
    dispatch_block_t update = ^{
        id identity = QualityVideo(video);
        if (identity) objc_setAssociatedObject(identity,SelectedQualityKey,label,OBJC_ASSOCIATION_COPY_NONATOMIC);
        NSUInteger matched = 0;
        for (UIView *overlay in QualityButtons.keyEnumerator.allObjects) {
            if (!identity || OverlayQualityVideo(overlay) != identity) continue;
            // Update immediately: the host can defer layout during native menu
            // transitions. A pending layout alone leaves the previous title up.
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
    if (OriginalQualitySelection) ((void (*)(id,SEL,id,id))OriginalQualitySelection)(self,cmd,video,format);
    RememberQuality(video,format,@"original-selector");
}
static void RedesignedQualitySelection(id self, SEL cmd, id video, id format) {
    if (OriginalRedesignedQualitySelection) ((void (*)(id,SEL,id,id))OriginalRedesignedQualitySelection)(self,cmd,video,format);
    RememberQuality(video,format,@"redesigned-selector");
}
static void FormatConstraint(id self, SEL cmd, id constraint) {
    if (OriginalFormatConstraint) ((void (*)(id,SEL,id))OriginalFormatConstraint)(self,cmd,constraint);
    // Modern native choices can apply the constraint directly. Only display an
    // actual native quality label, or clear a removed constraint (Auto).
    if (!constraint || [QualityObject(constraint,@"qualityLabel") isKindOfClass:NSString.class])
        RememberQuality(self,constraint,@"format-constraint");
}

void YTKACEInstallQualityControls(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        QualityButtons = [NSMapTable weakToWeakObjectsMapTable];
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
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            button.accessibilityLabel = YTKACELocalized(@"Video Quality");
            button.hidden = !YTKACEFeatureEnabled(QualityButtonKey);
        });
    });
}
