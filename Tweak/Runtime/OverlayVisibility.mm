#import "OverlayVisibility.h"
#import <objc/runtime.h>

static const void *YTKACEPinnedAlpha = &YTKACEPinnedAlpha;

void YTKACEKeepNativeOverlayVisible(id<YTKACENativeVisibilityTarget> target, BOOL keep) {
    NSNumber *baseline = objc_getAssociatedObject(target, YTKACEPinnedAlpha);
    if (keep && !target.hidden) {
        if (!baseline) objc_setAssociatedObject(target, YTKACEPinnedAlpha, @(target.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        target.alpha = 1.0;
    } else if (baseline) {
        // Restore only our own alpha, never an obsolete native hidden state.
        if (!target.hidden && target.alpha == 1.0) target.alpha = baseline.doubleValue;
        objc_setAssociatedObject(target, YTKACEPinnedAlpha, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
