#import <Foundation/Foundation.h>

// Matches CaptionIsland's per-video settings, without linking its dylib.
static inline NSDictionary *YTKACECaptionVideoOverridesRule(void) {
    NSDictionary *text = @{@"default":@"", @"maximumLength":@256};
    NSDictionary *language = @{@"default":@"", @"maximumLength":@35,
        @"pattern":@"^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$"};
    return @{@"default":@{}, @"maximumCount":@500,
        @"keyPattern":@"^[A-Za-z0-9_-]{1,128}$",
        @"valueRule":@{@"default":@{}, @"fields":@{
            @"searchTitle":text, @"searchArtist":text, @"originalTitle":text,
            @"captionAdvance":@{@"default":@0.0},
            @"captionLanguagePriorities":@{@"default":@[], @"maximumCount":@24, @"elementRule":language},
            @"captionSourcePreference":@{@"default":@0, @"values":@[@0,@1,@2]},
            @"lyricsSuppressed":@{@"default":@NO},
            @"updatedAt":@{@"default":@0.0, @"minimum":@0}
        }}};
}
