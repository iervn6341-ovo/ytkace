#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, YTKACEAdBlockingMode) {
    YTKACEAdBlockingModeOriginal = 0,
    YTKACEAdBlockingModeUYouEnhanced = 1,
};

FOUNDATION_EXPORT NSString * const YTKACEAdBlockingModeKey;
FOUNDATION_EXPORT YTKACEAdBlockingMode YTKACEPlaybackAdBlockingMode(void);
FOUNDATION_EXPORT void YTKACEInstallPlaybackAdsHooks(void);
