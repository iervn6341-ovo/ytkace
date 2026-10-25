#import "SettingsPlaybackHooks.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>
#include <atomic>
#include <cmath>
#include <cstring>

static __weak id YTKACESettingsPlayer;
static __weak id YTKACESettingsLocalPlayer;
static const void *YTKACESettingsObservedRate = &YTKACESettingsObservedRate;
static std::atomic<unsigned> YTKACESettingsInterruptionEpoch{0};
static std::atomic<bool> YTKACESettingsInterrupted{false};
static NSUInteger YTKACESettingsActivationGeneration;
static IMP OriginalActivation, OriginalRate, OriginalPush, OriginalPresent;
static IMP OriginalSettingsWillAppear, OriginalSettingsDidAppear;
static IMP OriginalPlayerWillDisappear, OriginalPlayerDidDisappear;
static IMP OriginalSettingsPauses[12];

static id YTKACESettingsObject(id target, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static BOOL YTKACEIsNativeSettings(UIViewController *controller) {
    Class cls = NSClassFromString(@"YTSettingsViewController");
    if (cls && [controller isKindOfClass:cls]) return YES;
    if ([controller isKindOfClass:UINavigationController.class]) {
        return YTKACEIsNativeSettings(((UINavigationController *)controller).topViewController);
    }
    return NO;
}

struct YTKACESettingsTransition;
static thread_local YTKACESettingsTransition *YTKACECurrentSettingsTransition;

// Only the synchronous native Settings presentation/lifecycle call owns this guard.
// There is no delayed resume and no time window that could swallow a user's later Pause.
struct YTKACESettingsTransition {
    YTKACESettingsTransition *previous;
    __weak id player, local, video;
    unsigned epoch;
    NSUInteger activationGeneration;
    bool enabled, wasPlaying;
    explicit YTKACESettingsTransition(bool nativeSettings) {
        previous = YTKACECurrentSettingsTransition;
        enabled = nativeSettings && NSThread.isMainThread &&
            YTKACEFeatureEnabled(@"YTKACE.Preference.Navigation.KeepPlayingInSettings");
        player = enabled ? YTKACESettingsPlayer : nil;
        local = enabled ? YTKACESettingsLocalPlayer : nil;
        video = YTKACESettingsObject(player, @"activeVideo");
        NSNumber *rate = video ? objc_getAssociatedObject(video, YTKACESettingsObservedRate) : nil;
        wasPlaying = rate && std::isfinite(rate.doubleValue) && rate.doubleValue > 0.001;
        epoch = YTKACESettingsInterruptionEpoch.load();
        activationGeneration = YTKACESettingsActivationGeneration;
        YTKACECurrentSettingsTransition = this;
    }
    ~YTKACESettingsTransition() { YTKACECurrentSettingsTransition = previous; }
};

static BOOL YTKACESuppressSettingsPause(id target) {
    if (!NSThread.isMainThread) return NO;
    for (YTKACESettingsTransition *scope = YTKACECurrentSettingsTransition; scope; scope = scope->previous) {
        id video = scope->video;
        if (scope->enabled && scope->wasPlaying && video != nil &&
            YTKACESettingsObject(scope->player, @"activeVideo") == video &&
            (target == scope->player || target == scope->local || target == video) &&
            UIApplication.sharedApplication.applicationState == UIApplicationStateActive &&
            !YTKACESettingsInterrupted.load() && scope->epoch == YTKACESettingsInterruptionEpoch.load() &&
            scope->activationGeneration == YTKACESettingsActivationGeneration) {
            NSLog(@"[YTKACE Settings Playback] Prevented native Settings transition pause (%@).", NSStringFromClass([target class]));
            return YES;
        }
    }
    return NO;
}

template<unsigned Index> static void YTKACESettingsPause(id receiver, SEL selector) {
    if (!YTKACESuppressSettingsPause(receiver) && OriginalSettingsPauses[Index])
        ((void (*)(id, SEL))OriginalSettingsPauses[Index])(receiver, selector);
}

static void YTKACESettingsActivation(id receiver, SEL selector, id local, id video, id data) {
    if (OriginalActivation) ((void (*)(id, SEL, id, id, id))OriginalActivation)(receiver, selector, local, video, data);
    if (NSThread.isMainThread) {
        YTKACESettingsPlayer = receiver;
        YTKACESettingsLocalPlayer = local;
        ++YTKACESettingsActivationGeneration;
    }
}
static void YTKACESettingsRate(id receiver, SEL selector, float rate) {
    objc_setAssociatedObject(receiver, YTKACESettingsObservedRate, @(rate), OBJC_ASSOCIATION_RETAIN);
    if (OriginalRate) ((void (*)(id, SEL, float))OriginalRate)(receiver, selector, rate);
}
static void YTKACESettingsPush(UINavigationController *receiver, SEL selector, UIViewController *destination, BOOL animated) {
    YTKACESettingsTransition scope(YTKACEIsNativeSettings(destination));
    if (OriginalPush) ((void (*)(id, SEL, id, BOOL))OriginalPush)(receiver, selector, destination, animated);
}
static void YTKACESettingsPresent(UIViewController *receiver, SEL selector, UIViewController *destination, BOOL animated, void (^completion)(void)) {
    YTKACESettingsTransition scope(YTKACEIsNativeSettings(destination));
    if (OriginalPresent) ((void (*)(id, SEL, id, BOOL, id))OriginalPresent)(receiver, selector, destination, animated, completion);
}
static void YTKACESettingsWillAppear(UIViewController *receiver, SEL selector, BOOL animated) {
    YTKACESettingsTransition scope(true);
    if (OriginalSettingsWillAppear) ((void (*)(id, SEL, BOOL))OriginalSettingsWillAppear)(receiver, selector, animated);
}
static void YTKACESettingsDidAppear(UIViewController *receiver, SEL selector, BOOL animated) {
    YTKACESettingsTransition scope(true);
    if (OriginalSettingsDidAppear) ((void (*)(id, SEL, BOOL))OriginalSettingsDidAppear)(receiver, selector, animated);
}
static BOOL YTKACEPlayerIsEnteringSettings(UIViewController *player) {
    id<UIViewControllerTransitionCoordinator> coordinator = player.transitionCoordinator;
    return coordinator != nil && YTKACEIsNativeSettings([coordinator viewControllerForKey:UITransitionContextToViewControllerKey]);
}
static void YTKACESettingsPlayerWillDisappear(UIViewController *receiver, SEL selector, BOOL animated) {
    YTKACESettingsTransition scope(YTKACEPlayerIsEnteringSettings(receiver));
    if (OriginalPlayerWillDisappear) ((void (*)(id, SEL, BOOL))OriginalPlayerWillDisappear)(receiver, selector, animated);
}
static void YTKACESettingsPlayerDidDisappear(UIViewController *receiver, SEL selector, BOOL animated) {
    YTKACESettingsTransition scope(YTKACEPlayerIsEnteringSettings(receiver));
    if (OriginalPlayerDidDisappear) ((void (*)(id, SEL, BOOL))OriginalPlayerDidDisappear)(receiver, selector, animated);
}

static BOOL YTKACESettingsHasSignature(NSString *className, NSString *name, const char *arguments) {
    NSMethodSignature *signature = [NSClassFromString(className) instanceMethodSignatureForSelector:NSSelectorFromString(name)];
    if (!signature || strcmp(signature.methodReturnType, "v") != 0 ||
        signature.numberOfArguments != strlen(arguments) + 2) return NO;
    for (NSUInteger i = 0; i < strlen(arguments); ++i)
        if ([signature getArgumentTypeAtIndex:i + 2][0] != arguments[i]) return NO;
    return YES;
}

void YTKACEInstallSettingsPlaybackHooks(void) {
    // Unknown private signatures are left alone, rather than invoking an incompatible ABI.
    if (!YTKACESettingsHasSignature(@"YTSingleVideoController", @"playerRateDidChange:", "f") ||
        !YTKACESettingsHasSignature(@"YTPlayerViewController", @"playbackController:didActivateVideo:withPlaybackData:", "@@@")) return;
    YTKACEInstallInstanceHook(@"YTSingleVideoController", @"playerRateDidChange:", (IMP)YTKACESettingsRate, &OriginalRate);
    YTKACEInstallInstanceHook(@"YTPlayerViewController", @"playbackController:didActivateVideo:withPlaybackData:", (IMP)YTKACESettingsActivation, &OriginalActivation);
    YTKACEInstallInstanceHook(@"UINavigationController", @"pushViewController:animated:", (IMP)YTKACESettingsPush, &OriginalPush);
    YTKACEInstallInstanceHook(@"UIViewController", @"presentViewController:animated:completion:", (IMP)YTKACESettingsPresent, &OriginalPresent);
    for (NSString *name in @[@"viewWillAppear:", @"viewDidAppear:"]) {
        if (!YTKACESettingsHasSignature(@"YTSettingsViewController", name, "B") &&
            !YTKACESettingsHasSignature(@"YTSettingsViewController", name, "c")) continue;
        BOOL willAppear = [name isEqual:@"viewWillAppear:"];
        YTKACEInstallInstanceHook(@"YTSettingsViewController", name,
            willAppear ? (IMP)YTKACESettingsWillAppear : (IMP)YTKACESettingsDidAppear,
            willAppear ? &OriginalSettingsWillAppear : &OriginalSettingsDidAppear);
    }
    YTKACEInstallInstanceHook(@"YTPlayerViewController", @"viewWillDisappear:", (IMP)YTKACESettingsPlayerWillDisappear, &OriginalPlayerWillDisappear);
    YTKACEInstallInstanceHook(@"YTPlayerViewController", @"viewDidDisappear:", (IMP)YTKACESettingsPlayerDidDisappear, &OriginalPlayerDidDisappear);
    const IMP replacements[] = {(IMP)YTKACESettingsPause<0>, (IMP)YTKACESettingsPause<1>,
        (IMP)YTKACESettingsPause<2>, (IMP)YTKACESettingsPause<3>, (IMP)YTKACESettingsPause<4>, (IMP)YTKACESettingsPause<5>,
        (IMP)YTKACESettingsPause<6>, (IMP)YTKACESettingsPause<7>, (IMP)YTKACESettingsPause<8>, (IMP)YTKACESettingsPause<9>,
        (IMP)YTKACESettingsPause<10>, (IMP)YTKACESettingsPause<11>};
    unsigned index = 0, installed = 0;
    for (NSString *cls in @[@"YTPlayerViewController", @"YTLocalPlaybackController", @"YTSingleVideoController"]) {
        for (NSString *name in @[@"pause", @"suspendPlayback", @"pauseVideo", @"pausePlayback"]) {
            if (YTKACESettingsHasSignature(cls, name, ""))
                installed += YTKACEInstallInstanceHook(cls, name, replacements[index], &OriginalSettingsPauses[index]) ? 1 : 0;
            ++index;
        }
    }
    NSLog(@"[YTKACE Settings Playback] Native Settings guard installed for %u compatible pause methods.", installed);
    [NSNotificationCenter.defaultCenter addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            BOOL began = [note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan;
            YTKACESettingsInterrupted.store(began);
            ++YTKACESettingsInterruptionEpoch;
        }];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil
        usingBlock:^(__unused NSNotification *note) { ++YTKACESettingsInterruptionEpoch; }];
}
