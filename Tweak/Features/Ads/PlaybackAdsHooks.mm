#import "PlaybackAdsHooks.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import "../Downloads/DownloadLog.h"

// Independently implemented runtime-hook equivalent of the video/Shorts
// uYouAdBlockingWorkaroundLite strategy in uYouEnhanced. See THIRD_PARTY_NOTICES.
// This does not load uYou.dylib or change the download resolver.
NSString * const YTKACEAdBlockingModeKey = @"YTKACE.Preference.Ads.PlaybackMode";

static IMP OriginalAdShieldSignals, OriginalAdShieldSignalsWithoutIDFA;
static IMP OriginalDataSignals, OriginalDataSignalsWithoutIDFA;
static IMP OriginalAdsDecorateContext, OriginalAccountAdsDecorateContext;
static IMP OriginalPlayerAdsArray, OriginalAdSlotsArray, OriginalAdPlacementsArray;
static IMP OriginalAdBreakParams, OriginalAdNextParams, OriginalAdParams;
static IMP OriginalEnableSkippableAd, OriginalDisableIDFA, OriginalEncodedContext;
static IMP OriginalIsMonetized, OriginalMDXSessionImplAdPlaying, OriginalMDXSessionAdPlaying;
static IMP OriginalIsPlayingAd, OriginalIsPlayingAdSurvey, OriginalIsPlayingAdIntro;
static IMP OriginalCreateAdsPlaybackCoordinator;

YTKACEAdBlockingMode YTKACEPlaybackAdBlockingMode(void) {
    id value = YTKACEPreferenceObject(YTKACEAdBlockingModeKey);
    return [value respondsToSelector:@selector(integerValue)] &&
        [value integerValue] == YTKACEAdBlockingModeOriginal
        ? YTKACEAdBlockingModeOriginal : YTKACEAdBlockingModeUYouEnhanced;
}

static BOOL Blocking(void) { return YTKACEFeatureEnabled(YTKACENoAdsKey); }
static BOOL UYouStrategy(void) {
    return Blocking() && YTKACEPlaybackAdBlockingMode() == YTKACEAdBlockingModeUYouEnhanced;
}
static BOOL ExtraPlayerHooks(void) {
    return Blocking() && YTKACEPlaybackAdBlockingMode() == YTKACEAdBlockingModeOriginal;
}
static id ObjectGetter(IMP original, id receiver, SEL selector) {
    return original != NULL ? ((id (*)(id, SEL))original)(receiver, selector) : nil;
}
static BOOL BoolGetter(IMP original, id receiver, SEL selector) {
    return original != NULL && ((BOOL (*)(id, SEL))original)(receiver, selector);
}
static id EmptySignals(IMP original, id receiver, SEL selector) {
    return Blocking() ? @{} : ObjectGetter(original, receiver, selector);
}
static id AdShieldSignals(id receiver, SEL selector) {
    return EmptySignals(OriginalAdShieldSignals, receiver, selector);
}
static id AdShieldSignalsWithoutIDFA(id receiver, SEL selector) {
    return EmptySignals(OriginalAdShieldSignalsWithoutIDFA, receiver, selector);
}
static id DataSignals(id receiver, SEL selector) {
    if (UYouStrategy()) return @{@"ms": @""};
    return EmptySignals(OriginalDataSignals, receiver, selector);
}
static id DataSignalsWithoutIDFA(id receiver, SEL selector) {
    return EmptySignals(OriginalDataSignalsWithoutIDFA, receiver, selector);
}
static void Decorate(IMP original, id receiver, SEL selector, id context) {
    if (original != NULL) {
        // uYouEnhanced calls the original once with nil; it does not simply
        // skip the decorator. Off/original mode preserves the caller's context.
        ((void (*)(id, SEL, id))original)(receiver, selector, UYouStrategy() ? nil : context);
    }
}
static void AdsDecorate(id receiver, SEL selector, id context) {
    Decorate(OriginalAdsDecorateContext, receiver, selector, context);
}
static void AccountAdsDecorate(id receiver, SEL selector, id context) {
    Decorate(OriginalAccountAdsDecorateContext, receiver, selector, context);
}
static id PlayerAds(id receiver, SEL selector) {
    return Blocking() ? [NSMutableArray array] : ObjectGetter(OriginalPlayerAdsArray, receiver, selector);
}
static id AdSlots(id receiver, SEL selector) {
    return Blocking() ? [NSMutableArray array] : ObjectGetter(OriginalAdSlotsArray, receiver, selector);
}
static id AdPlacements(id receiver, SEL selector) {
    return ExtraPlayerHooks() ? [NSMutableArray array] : ObjectGetter(OriginalAdPlacementsArray, receiver, selector);
}
static id AdBreakParams(id receiver, SEL selector) {
    return ExtraPlayerHooks() ? nil : ObjectGetter(OriginalAdBreakParams, receiver, selector);
}
static id AdNextParams(id receiver, SEL selector) {
    return ExtraPlayerHooks() ? nil : ObjectGetter(OriginalAdNextParams, receiver, selector);
}
static id AdParams(id receiver, SEL selector) {
    return ExtraPlayerHooks() ? nil : ObjectGetter(OriginalAdParams, receiver, selector);
}
static BOOL SkippableAd(id receiver, SEL selector) {
    return Blocking() ? YES : BoolGetter(OriginalEnableSkippableAd, receiver, selector);
}
static BOOL DisableIDFA(id receiver, SEL selector) {
    return UYouStrategy() ? NO : BoolGetter(OriginalDisableIDFA, receiver, selector);
}
static BOOL EncodedContext(id receiver, SEL selector) {
    return UYouStrategy() ? NO : BoolGetter(OriginalEncodedContext, receiver, selector);
}
static BOOL IsMonetized(id receiver, SEL selector) {
    return UYouStrategy() ? NO : BoolGetter(OriginalIsMonetized, receiver, selector);
}
static void MDXImplAdPlaying(id receiver, SEL selector, id ad) {
    if (!ExtraPlayerHooks() && OriginalMDXSessionImplAdPlaying != NULL) {
        ((void (*)(id, SEL, id))OriginalMDXSessionImplAdPlaying)(receiver, selector, ad);
    }
}
static void MDXAdPlaying(id receiver, SEL selector, id ad) {
    if (!Blocking() && OriginalMDXSessionAdPlaying != NULL) {
        ((void (*)(id, SEL, id))OriginalMDXSessionAdPlaying)(receiver, selector, ad);
    }
}
static BOOL IsPlayingAd(id receiver, SEL selector) {
    return ExtraPlayerHooks() ? NO : BoolGetter(OriginalIsPlayingAd, receiver, selector);
}
static BOOL IsPlayingAdSurvey(id receiver, SEL selector) {
    return ExtraPlayerHooks() ? NO : BoolGetter(OriginalIsPlayingAdSurvey, receiver, selector);
}
static BOOL IsPlayingAdIntro(id receiver, SEL selector) {
    return ExtraPlayerHooks() ? NO : BoolGetter(OriginalIsPlayingAdIntro, receiver, selector);
}
static id CreateAdsCoordinator(id receiver, SEL selector) {
    // Do not initialize an ad coordinator only to discard it. Its initializer
    // can register observers or schedule work before returning its result.
    if (UYouStrategy()) return nil;
    id coordinator = ObjectGetter(OriginalCreateAdsPlaybackCoordinator, receiver, selector);
    return Blocking() ? nil : coordinator;
}

static BOOL InstallBoolean(NSString *className, NSString *selectorName,
                           IMP replacement, IMP *original) {
    Class cls = NSClassFromString(className);
    Method method = cls != Nil ? class_getInstanceMethod(cls, NSSelectorFromString(selectorName)) : NULL;
    if (method == NULL || method_getNumberOfArguments(method) != 2) return NO;
    char type[8] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (type[0] != 'B' && type[0] != 'c') return NO;
    return YTKACEInstallInstanceHook(className, selectorName, replacement, original);
}

void YTKACEInstallPlaybackAdsHooks(void) {
    YTKACEInstallClassHook(@"YTAdShieldUtils", @"spamSignalsDictionary", (IMP)AdShieldSignals, &OriginalAdShieldSignals);
    YTKACEInstallClassHook(@"YTAdShieldUtils", @"spamSignalsDictionaryWithoutIDFA", (IMP)AdShieldSignalsWithoutIDFA, &OriginalAdShieldSignalsWithoutIDFA);
    YTKACEInstallClassHook(@"YTDataUtils", @"spamSignalsDictionary", (IMP)DataSignals, &OriginalDataSignals);
    YTKACEInstallClassHook(@"YTDataUtils", @"spamSignalsDictionaryWithoutIDFA", (IMP)DataSignalsWithoutIDFA, &OriginalDataSignalsWithoutIDFA);
    BOOL decorator = YTKACEInstallInstanceHook(@"YTAdsInnerTubeContextDecorator", @"decorateContext:", (IMP)AdsDecorate, &OriginalAdsDecorateContext);
    BOOL accountDecorator = YTKACEInstallInstanceHook(@"YTAccountScopedAdsInnerTubeContextDecorator", @"decorateContext:", (IMP)AccountAdsDecorate, &OriginalAccountAdsDecorateContext);

    // Keep absent private APIs absent, especially on older YouTube releases.
    YTKACEInstallInstanceHook(@"YTIPlayerResponse", @"playerAdsArray", (IMP)PlayerAds, &OriginalPlayerAdsArray);
    YTKACEInstallInstanceHook(@"YTIPlayerResponse", @"adSlotsArray", (IMP)AdSlots, &OriginalAdSlotsArray);
    YTKACEInstallInstanceHook(@"YTIPlayerResponse", @"adPlacementsArray", (IMP)AdPlacements, &OriginalAdPlacementsArray);
    YTKACEInstallInstanceHook(@"YTIPlayerResponse", @"adBreakParams", (IMP)AdBreakParams, &OriginalAdBreakParams);
    YTKACEInstallInstanceHook(@"YTIPlayerResponse", @"adNextParams", (IMP)AdNextParams, &OriginalAdNextParams);
    YTKACEInstallInstanceHook(@"YTIPlayerResponse", @"adParams", (IMP)AdParams, &OriginalAdParams);
    BOOL monetized = InstallBoolean(@"YTIPlayerResponse", @"isMonetized", (IMP)IsMonetized, &OriginalIsMonetized);
    InstallBoolean(@"YTIClientMdxGlobalConfig", @"enableSkippableAd", (IMP)SkippableAd, &OriginalEnableSkippableAd);
    BOOL idfa = InstallBoolean(@"YTHotConfig", @"disableAfmaIdfaCollection", (IMP)DisableIDFA, &OriginalDisableIDFA);
    BOOL encoded = InstallBoolean(@"YTHotConfig", @"clientInfraClientConfigIosEnableFillingEncodedHacksInnertubeContext", (IMP)EncodedContext, &OriginalEncodedContext);

    YTKACEInstallInstanceHook(@"MDXSessionImpl", @"adPlaying:", (IMP)MDXImplAdPlaying, &OriginalMDXSessionImplAdPlaying);
    YTKACEInstallInstanceHook(@"MDXSession", @"adPlaying:", (IMP)MDXAdPlaying, &OriginalMDXSessionAdPlaying);
    InstallBoolean(@"YTLocalPlaybackController", @"isPlayingAd", (IMP)IsPlayingAd, &OriginalIsPlayingAd);
    InstallBoolean(@"YTLocalPlaybackController", @"isPlayingAdSurvey", (IMP)IsPlayingAdSurvey, &OriginalIsPlayingAdSurvey);
    InstallBoolean(@"YTLocalPlaybackController", @"isPlayingAdIntro", (IMP)IsPlayingAdIntro, &OriginalIsPlayingAdIntro);
    BOOL coordinator = YTKACEInstallInstanceHook(@"YTLocalPlaybackController", @"createAdsPlaybackCoordinator", (IMP)CreateAdsCoordinator, &OriginalCreateAdsPlaybackCoordinator);
    NSString *status = [NSString stringWithFormat:
        @"playbackMode=%ld enabled=%d hooks coordinator=%d decorators=%d/%d config=%d/%d monetized=%d",
        (long)YTKACEPlaybackAdBlockingMode(), Blocking(), coordinator,
        decorator, accountDecorator, idfa, encoded, monetized];
    NSLog(@"[YTKACE Ads] %@", status);
    YTKACEDownloadLog(@"ads", @"%@", status);
}
