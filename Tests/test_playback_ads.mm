#import <Foundation/Foundation.h>
#import "../Tweak/Features/Ads/PlaybackAdsHooks.h"
#import "../Tweak/Runtime/Preferences.h"
#import "../Tweak/Features/Downloads/DownloadLog.h"
#include <cassert>

// Test the actual policy module and hook installer, without UIKit or YouTube.
NSString * const YTKACENoAdsKey = @"test.removeAds";
static BOOL removeAds = YES, masterEnabled = YES;
static NSNumber *storedMode;
BOOL YTKACEFeatureEnabled(NSString *key) {
    return masterEnabled && removeAds && [key isEqualToString:YTKACENoAdsKey];
}
id YTKACEPreferenceObject(NSString *key) {
    return [key isEqualToString:YTKACEAdBlockingModeKey] ? storedMode : nil;
}
void YTKACEDownloadLog(NSString *, NSString *, ...) {}

@interface YTFakeSignals : NSObject
+ (NSDictionary *)spamSignalsDictionary;
+ (NSDictionary *)spamSignalsDictionaryWithoutIDFA;
@end
@implementation YTFakeSignals
+ (NSDictionary *)spamSignalsDictionary { return @{@"native": @YES}; }
+ (NSDictionary *)spamSignalsDictionaryWithoutIDFA { return @{@"native": @YES}; }
@end
@interface YTAdShieldUtils : YTFakeSignals @end
@implementation YTAdShieldUtils @end
@interface YTDataUtils : YTFakeSignals @end
@implementation YTDataUtils @end

static NSUInteger decorateCalls, accountDecorateCalls, coordinatorCalls, mdxCalls, mdxImplCalls;
static id decoratedContext, accountDecoratedContext;
@interface YTAdsInnerTubeContextDecorator : NSObject
- (void)decorateContext:(id)context;
@end
@implementation YTAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context { ++decorateCalls; decoratedContext = context; }
@end
@interface YTAccountScopedAdsInnerTubeContextDecorator : NSObject
- (void)decorateContext:(id)context;
@end
@implementation YTAccountScopedAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context { ++accountDecorateCalls; accountDecoratedContext = context; }
@end

@interface YTHotConfig : NSObject
- (BOOL)disableAfmaIdfaCollection;
- (BOOL)clientInfraClientConfigIosEnableFillingEncodedHacksInnertubeContext;
@end
@implementation YTHotConfig
- (BOOL)disableAfmaIdfaCollection { return YES; }
- (BOOL)clientInfraClientConfigIosEnableFillingEncodedHacksInnertubeContext { return YES; }
@end
@interface YTIPlayerResponse : NSObject
- (NSArray *)playerAdsArray;
- (NSArray *)adSlotsArray;
- (NSArray *)adPlacementsArray;
- (id)adBreakParams;
- (id)adNextParams;
- (id)adParams;
- (BOOL)isMonetized;
@end
@implementation YTIPlayerResponse
- (NSArray *)playerAdsArray { return @[@"native"]; }
- (NSArray *)adSlotsArray { return @[@"native"]; }
- (NSArray *)adPlacementsArray { return @[@"native"]; }
- (id)adBreakParams { return @"break"; }
- (id)adNextParams { return @"next"; }
- (id)adParams { return @"params"; }
- (BOOL)isMonetized { return YES; }
@end
@interface YTIClientMdxGlobalConfig : NSObject
- (BOOL)enableSkippableAd;
@end
@implementation YTIClientMdxGlobalConfig
- (BOOL)enableSkippableAd { return NO; }
@end
@interface MDXSession : NSObject
- (void)adPlaying:(id)ad;
@end
@implementation MDXSession
- (void)adPlaying:(id)ad { ++mdxCalls; }
@end
@interface MDXSessionImpl : NSObject
- (void)adPlaying:(id)ad;
@end
@implementation MDXSessionImpl
- (void)adPlaying:(id)ad { ++mdxImplCalls; }
@end
@interface YTLocalPlaybackController : NSObject
- (BOOL)isPlayingAd;
- (BOOL)isPlayingAdSurvey;
- (BOOL)isPlayingAdIntro;
- (id)createAdsPlaybackCoordinator;
@end
@implementation YTLocalPlaybackController
- (BOOL)isPlayingAd { return YES; }
- (BOOL)isPlayingAdSurvey { return YES; }
- (BOOL)isPlayingAdIntro { return YES; }
- (id)createAdsPlaybackCoordinator { ++coordinatorCalls; return @"coordinator"; }
@end

static void CheckPolicy(NSInteger mode, BOOL enabled, BOOL master) {
    storedMode = @(mode);
    removeAds = enabled;
    masterEnabled = master;
    const BOOL blocking = enabled && master;
    const BOOL uyou = blocking && mode == 1;
    const BOOL extra = blocking && mode == 0;
    YTLocalPlaybackController *player = [YTLocalPlaybackController new];
    coordinatorCalls = 0;
    id coordinator = [player createAdsPlaybackCoordinator];
    assert(coordinatorCalls == (uyou ? 0u : 1u));
    assert((coordinator == nil) == blocking);
    assert(player.isPlayingAd == !extra);
    assert(player.isPlayingAdSurvey == !extra);
    assert(player.isPlayingAdIntro == !extra);

    YTIPlayerResponse *response = [YTIPlayerResponse new];
    assert(response.playerAdsArray.count == (blocking ? 0u : 1u));
    assert(response.adSlotsArray.count == (blocking ? 0u : 1u));
    assert(response.adPlacementsArray.count == (extra ? 0u : 1u));
    assert((response.adBreakParams == nil) == extra);
    assert((response.adNextParams == nil) == extra);
    assert((response.adParams == nil) == extra);
    assert(response.isMonetized == !uyou);
    assert([YTIClientMdxGlobalConfig new].enableSkippableAd == blocking);
    YTHotConfig *config = [YTHotConfig new];
    assert(config.disableAfmaIdfaCollection == !uyou);
    assert(config.clientInfraClientConfigIosEnableFillingEncodedHacksInnertubeContext == !uyou);

    id context = [NSObject new];
    decorateCalls = accountDecorateCalls = 0;
    [[YTAdsInnerTubeContextDecorator new] decorateContext:context];
    [[YTAccountScopedAdsInnerTubeContextDecorator new] decorateContext:context];
    assert(decorateCalls == 1 && accountDecorateCalls == 1);
    assert(decoratedContext == (uyou ? nil : context));
    assert(accountDecoratedContext == (uyou ? nil : context));
    NSDictionary *expected = !blocking ? @{@"native": @YES} : uyou ? @{@"ms": @""} : @{};
    assert([[YTDataUtils spamSignalsDictionary] isEqual:expected]);
    assert([YTDataUtils spamSignalsDictionaryWithoutIDFA].count == (blocking ? 0u : 1u));
    assert([YTAdShieldUtils spamSignalsDictionary].count == (blocking ? 0u : 1u));
    assert([YTAdShieldUtils spamSignalsDictionaryWithoutIDFA].count == (blocking ? 0u : 1u));
    mdxCalls = mdxImplCalls = 0;
    [[MDXSession new] adPlaying:context];
    [[MDXSessionImpl new] adPlaying:context];
    assert(mdxCalls == (blocking ? 0u : 1u));
    assert(mdxImplCalls == (extra ? 0u : 1u));
    // Installing hooks on subclasses must not mutate their parent class.
    assert([YTFakeSignals spamSignalsDictionary].count == 1);
}

int main() {
    @autoreleasepool {
        assert(YTKACEPlaybackAdBlockingMode() == YTKACEAdBlockingModeUYouEnhanced);
        storedMode = @99;
        assert(YTKACEPlaybackAdBlockingMode() == YTKACEAdBlockingModeUYouEnhanced);
        YTKACEInstallPlaybackAdsHooks();
        for (NSInteger mode = 0; mode <= 1; ++mode) {
            CheckPolicy(mode, YES, YES);
            CheckPolicy(mode, NO, YES);
            CheckPolicy(mode, YES, NO);
        }
        YTKACEInstallPlaybackAdsHooks();
        CheckPolicy(1, YES, YES); // Reinstallation does not corrupt originals.
    }
}
