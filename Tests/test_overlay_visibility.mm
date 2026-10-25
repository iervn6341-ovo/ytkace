#import <Foundation/Foundation.h>
#import "../Tweak/Runtime/OverlayVisibility.h"
#include <cassert>

@interface NativeControl : NSObject <YTKACENativeVisibilityTarget>
@property(nonatomic, getter=isHidden) BOOL hidden;
@property(nonatomic) CGFloat alpha;
@end
@implementation NativeControl
@end

int main() {
    @autoreleasepool {
        NativeControl *play = [NativeControl new], *replay = [NativeControl new];
        play.alpha = 0.25;
        replay.hidden = YES;
        replay.alpha = 0;
        YTKACEKeepNativeOverlayVisible(play, YES);
        YTKACEKeepNativeOverlayVisible(replay, YES);
        assert(!play.hidden && play.alpha == 1);
        assert(replay.hidden && replay.alpha == 0); // Inactive alternative stays inactive.
        // YouTube changes state while keep-visible remains enabled.
        play.hidden = YES;
        replay.hidden = NO;
        replay.alpha = 0.5;
        YTKACEKeepNativeOverlayVisible(play, YES);
        YTKACEKeepNativeOverlayVisible(replay, YES);
        assert(play.hidden && !replay.hidden && replay.alpha == 1);
        YTKACEKeepNativeOverlayVisible(play, NO);
        YTKACEKeepNativeOverlayVisible(replay, NO);
        assert(play.hidden && !replay.hidden && replay.alpha == 0.5);
        // A native alpha update during a state change must not be overwritten on disable.
        YTKACEKeepNativeOverlayVisible(replay, YES);
        replay.alpha = 0.2;
        YTKACEKeepNativeOverlayVisible(replay, NO);
        assert(replay.alpha == 0.2 && !replay.hidden);
        puts("Overlay visibility preserves native play/replay states across preference changes.");
    }
}
