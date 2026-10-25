#import <Foundation/Foundation.h>
#import <CoreGraphics/CGBase.h>

@protocol YTKACENativeVisibilityTarget <NSObject>
@property(nonatomic, getter=isHidden) BOOL hidden;
@property(nonatomic) CGFloat alpha;
@end

// Native hidden flags select mutually exclusive controls and must never be overridden.
FOUNDATION_EXPORT void YTKACEKeepNativeOverlayVisible(id<YTKACENativeVisibilityTarget> target, BOOL keep);
