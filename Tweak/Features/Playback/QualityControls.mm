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

static IMP OriginalQualitySelection, OriginalRedesignedQualitySelection;
static const void *SelectedQualityKey = &SelectedQualityKey;
static NSHashTable<UIView *> *QualityOverlays;
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
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object,selector);
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

static void RememberQuality(id video, id format) {
    NSString *label = QualityObject(format,@"qualityLabel");
    if (![label isKindOfClass:NSString.class]) label = nil;
    dispatch_block_t update = ^{
        if (video) objc_setAssociatedObject(video,SelectedQualityKey,label,OBJC_ASSOCIATION_COPY_NONATOMIC);
        for (UIView *overlay in QualityOverlays.allObjects) [overlay setNeedsLayout];
    };
    if (NSThread.isMainThread) update(); else dispatch_async(dispatch_get_main_queue(),update);
}
static void QualitySelection(id self, SEL cmd, id video, id format) {
    if (OriginalQualitySelection) ((void (*)(id,SEL,id,id))OriginalQualitySelection)(self,cmd,video,format);
    RememberQuality(video,format);
}
static void RedesignedQualitySelection(id self, SEL cmd, id video, id format) {
    if (OriginalRedesignedQualitySelection) ((void (*)(id,SEL,id,id))OriginalRedesignedQualitySelection)(self,cmd,video,format);
    RememberQuality(video,format);
}

void YTKACEInstallQualityControls(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        QualityOverlays = [NSHashTable weakObjectsHashTable];
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSDictionary *stored = [defaults persistentDomainForName:NSBundle.mainBundle.bundleIdentifier ?: @""];
        id legacy = stored[@"YTVideoOverlay-YouQuality-Enabled"];
        if (!stored[QualityButtonKey] && legacy) [defaults setBool:[legacy boolValue] forKey:QualityButtonKey];
        [defaults registerDefaults:@{QualityButtonKey:@YES}];
        YTKACEInstallInstanceHook(@"YTVideoQualitySwitchOriginalController",@"singleVideo:didSelectVideoFormat:",
            (IMP)QualitySelection,&OriginalQualitySelection);
        YTKACEInstallInstanceHook(@"YTVideoQualitySwitchRedesignedController",@"singleVideo:didSelectVideoFormat:",
            (IMP)RedesignedQualitySelection,&OriginalRedesignedQualitySelection);
        YTKACERegisterOverlayConfigurator(@"quality", ^(UIView *overlay, UIStackView *stack) {
            [QualityOverlays addObject:overlay];
            YTKACEQualityControls *controls = YTKACEQualityControls.shared;
            controls.overlay = overlay;
            UIButton *button = YTKACEOverlayButton(stack,@"YTKACE Quality",@"gearshape",controls,@selector(openQuality:));
            controls.button = button;
            id video = QualityObject(QualityObject(overlay,@"playerViewController"),@"activeVideo");
            NSString *label = video ? objc_getAssociatedObject(video,SelectedQualityKey) : nil;
            NSString *title = YTKACEQualityButtonTitle(label);
            if (![button.currentTitle isEqual:title]) [button setTitle:title forState:UIControlStateNormal];
            [button setImage:nil forState:UIControlStateNormal];
            button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            button.accessibilityLabel = YTKACELocalized(@"Video Quality");
            button.accessibilityValue = label ?: YTKACELocalized(@"Auto");
            button.hidden = !YTKACEFeatureEnabled(QualityButtonKey);
        });
    });
}
