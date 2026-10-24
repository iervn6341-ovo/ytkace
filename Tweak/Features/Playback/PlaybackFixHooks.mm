/*
 * Playback error recovery adapted from YTPlaybackFix by Mark02.
 * https://github.com/Mark02-2012/YTPlaybackFix
 *
 * Copyright (c) 2026 Mark02
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import "../Downloads/DownloadLog.h"
#import "../Ads/PlaybackAdsHooks.h"
#include "PlaybackRecoveryPolicy.hpp"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const YTKACEPlaybackFixKey = @"YTKACE.Preference.Playback.Fix";
static NSString *const YTKACEPlaybackErrorDomain =
    @"com.google.ios.youtube.ErrorDomain.playback";
static IMP OriginalHandleError;
static const void *YTKACERecoveryStateKey = &YTKACERecoveryStateKey;

@interface YTKACEPlaybackRecoveryState : NSObject {
@public
    ytkace::PlaybackRecoveryBudget budget;
}
@property(nonatomic, copy) NSString *videoID;
@property(nonatomic, weak) id player;
@end

@implementation YTKACEPlaybackRecoveryState
@end

NSInteger YTKACEPlaybackFixMode(void) {
    if (!YTKACEMasterEnabled()) return 0;
    id stored = YTKACEPreferenceObject(@"YTKACE.Preference.Playback.FixMode");
    if ([stored respondsToSelector:@selector(integerValue)]) {
        const NSInteger mode = [stored integerValue];
        return mode >= 0 && mode <= 2 ? mode : 0;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Playback.HLSMode")) return 2;
    return YTKACEFeatureEnabled(YTKACEPlaybackFixKey) ? 1 : 0;
}

static id YTKACEParentResponder(id overlay) {
    SEL responderGetter = NSSelectorFromString(@"parentResponder");
    if (![overlay respondsToSelector:responderGetter]) {
        YTKACEDownloadLog(@"fix", @"parentResponder unavailable");
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(overlay, responderGetter);
}

static void YTKACESendRetryEvent(id overlay, NSString *stage) {
    id responder = YTKACEParentResponder(overlay);
    if (responder == nil) {
        YTKACEDownloadLog(@"fix", @"%@ no responder", stage);
        return;
    }
    Class eventClass = NSClassFromString(@"YTPlayerTapToRetryResponderEvent");
    SEL factory = NSSelectorFromString(@"eventWithFirstResponder:");
    if (eventClass == Nil || ![eventClass respondsToSelector:factory]) {
        YTKACEDownloadLog(@"fix", @"%@ event class missing", stage);
        return;
    }
    id event = ((id (*)(Class, SEL, id))objc_msgSend)(eventClass, factory,
                                                      responder);
    SEL send = NSSelectorFromString(@"send");
    if (event == nil || ![event respondsToSelector:send]) {
        YTKACEDownloadLog(@"fix", @"%@ event not created", stage);
        return;
    }
    ((void (*)(id, SEL))objc_msgSend)(event, send);
    YTKACEDownloadLog(@"fix", @"%@ retry event sent to %@", stage,
                      NSStringFromClass([responder class]));
}

static BOOL YTKACEReloadPlayer(id pvc, NSString *stage) {
    SEL activeGetter = NSSelectorFromString(@"activeVideo");
    if (pvc == nil || ![pvc respondsToSelector:activeGetter]) return NO;
    id video = ((id (*)(id, SEL))objc_msgSend)(pvc, activeGetter);
    SEL reloadSel = NSSelectorFromString(@"player:reloadWithContext:");
    SEL mediaGetter = NSSelectorFromString(@"mediaPlayer");
    Class contextClass = NSClassFromString(@"MLPlayerReloadContext");
    SEL contextInit = NSSelectorFromString(
        @"initWithStartPlayback:refreshStreamingData:");
    if (video == nil || contextClass == Nil ||
        ![video respondsToSelector:reloadSel] ||
        ![video respondsToSelector:mediaGetter]) {
        YTKACEDownloadLog(@"fix", @"%@ player reload unavailable on %@", stage,
                          video == nil ? @"nil" : NSStringFromClass([video class]));
        return NO;
    }
    id allocated = [contextClass alloc];
    if (![allocated respondsToSelector:contextInit]) return NO;
    id context = ((id (*)(id, SEL, BOOL, BOOL))objc_msgSend)(
        allocated, contextInit, YES, YES);
    if (context == nil) return NO;
    id media = ((id (*)(id, SEL))objc_msgSend)(video, mediaGetter);
    ((void (*)(id, SEL, id, id))objc_msgSend)(video, reloadSel, media, context);
    YTKACEDownloadLog(@"fix", @"%@ player reload on %@", stage,
                      NSStringFromClass([video class]));
    return YES;
}

static void YTKACESeek(id player, double position, NSString *stage) {
    SEL seek = NSSelectorFromString(@"seekToTime:");
    if (![player respondsToSelector:seek]) {
        YTKACEDownloadLog(@"fix", @"%@ seek unavailable", stage);
        return;
    }
    ((void (*)(id, SEL, double))objc_msgSend)(player, seek, position);
    YTKACEDownloadLog(@"fix", @"%@ seek %.2f", stage, position);
}

static NSString *YTKACERecoveryVideoID(id player) {
    SEL getter = NSSelectorFromString(@"currentVideoID");
    if (![player respondsToSelector:getter]) return nil;
    id value = ((id (*)(id, SEL))objc_msgSend)(player, getter);
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static id YTKACERecoveryPlayer(id overlay) {
    id current = overlay;
    for (NSUInteger depth = 0; current != nil && depth < 6; ++depth) {
        if ([current respondsToSelector:NSSelectorFromString(@"activeVideo")] &&
            YTKACERecoveryVideoID(current).length != 0) return current;
        id next = nil;
        for (NSString *name in @[@"parentViewController", @"parentResponder"]) {
            SEL getter = NSSelectorFromString(name);
            if ([current respondsToSelector:getter]) {
                next = ((id (*)(id, SEL))objc_msgSend)(current, getter);
                if (next != nil && next != current) break;
            }
        }
        if (next == current) break;
        current = next;
    }
    return nil;
}

static double YTKACEPosition(id player) {
    SEL time = NSSelectorFromString(@"currentVideoMediaTime");
    return [player respondsToSelector:time]
        ? ((double (*)(id, SEL))objc_msgSend)(player, time) : -1.0;
}

static void YTKACEScheduleCaptionRestore(id player) {
    __weak id weakPlayer = player;
    NSString *videoID = [YTKACERecoveryVideoID(player) copy];
    for (NSNumber *delay in @[@0.6, @1.5, @3.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
            (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            id current = weakPlayer;
            if (current != nil &&
                [YTKACERecoveryVideoID(current) isEqualToString:videoID]) {
                YTKACECaptionsRestore(current);
            }
        });
    }
}

static BOOL YTKACERecoveryStillCurrent(id overlay,
                                       YTKACEPlaybackRecoveryState *state) {
    return overlay != nil && state.player != nil &&
        YTKACEPlaybackFixMode() == 1 &&
        objc_getAssociatedObject(overlay, YTKACERecoveryStateKey) == state &&
        [YTKACERecoveryVideoID(state.player) isEqualToString:state.videoID];
}

static void YTKACECallOriginalHandleError(id receiver, SEL selector, id error) {
    if (OriginalHandleError != NULL) {
        ((void (*)(id, SEL, id))OriginalHandleError)(receiver, selector, error);
    }
}

static void YTKACEHandleError(id receiver, SEL selector, id error) {
    if (!NSThread.isMainThread) {
        __weak id weakReceiver = receiver;
        dispatch_async(dispatch_get_main_queue(), ^{
            id overlay = weakReceiver;
            if (overlay != nil) YTKACEHandleError(overlay, selector, error);
        });
        return;
    }
    NSError *failure = [error isKindOfClass:NSError.class] ? error : nil;
    const NSInteger mode = YTKACEPlaybackFixMode();
    // Keep the error visible in macOS Console without exposing stream URLs,
    // credentials, or server response bodies.
    NSLog(@"[YTKACE Playback] mode=%ld domain=%@ code=%ld adMode=%ld ads=%d",
          (long)mode, failure.domain ?: NSStringFromClass([error class]),
          (long)failure.code, (long)YTKACEPlaybackAdBlockingMode(),
          YTKACEFeatureEnabled(YTKACENoAdsKey));
    YTKACEDownloadLog(@"fix", @"handleError mode=%ld domain=%@ code=%ld adMode=%ld ads=%d",
        (long)mode, failure.domain ?: @"unknown", (long)failure.code,
        (long)YTKACEPlaybackAdBlockingMode(), YTKACEFeatureEnabled(YTKACENoAdsKey));
    id player = YTKACERecoveryPlayer(receiver);
    NSString *videoID = YTKACERecoveryVideoID(player);

    if (mode == 2) {
        __weak id weakReceiver = receiver;
        __weak id weakPlayer = player;
        BOOL started = videoID.length != 0 &&
            YTKACEHLSBeginFallback(videoID, ^(BOOL available) {
                id overlay = weakReceiver;
                id current = weakPlayer;
                if (overlay == nil || current == nil ||
                    YTKACEPlaybackFixMode() != 2 ||
                    ![YTKACERecoveryVideoID(current) isEqualToString:videoID]) return;
                if (available && YTKACEReloadPlayer(current, @"hls fallback")) return;
                YTKACECallOriginalHandleError(overlay, selector, error);
            });
        if (!started) YTKACECallOriginalHandleError(receiver, selector, error);
        return;
    }
    if (mode != 1 || player == nil || videoID.length == 0 ||
        ![failure.domain isEqualToString:YTKACEPlaybackErrorDomain] ||
        (failure.code != 14 && failure.code != 0)) {
        YTKACECallOriginalHandleError(receiver, selector, error);
        return;
    }

    YTKACEPlaybackRecoveryState *state =
        objc_getAssociatedObject(receiver, YTKACERecoveryStateKey);
    if (state == nil || state.player != player ||
        ![state.videoID isEqualToString:videoID]) {
        state = [YTKACEPlaybackRecoveryState new];
        state.videoID = videoID;
        state.player = player;
        objc_setAssociatedObject(receiver, YTKACERecoveryStateKey, state,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (state->budget.inFlight()) return;
    if (!state->budget.begin(NSProcessInfo.processInfo.systemUptime)) {
        YTKACEDownloadLog(@"fix", @"retry limit reached; restoring native error UI");
        YTKACECallOriginalHandleError(receiver, selector, error);
        return;
    }

    double saved = YTKACEPosition(player);
    const double savedTime = std::isfinite(saved) && saved >= 0 ? saved : 0;
    __weak id weakReceiver = receiver;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        id overlay = weakReceiver;
        id current = state.player;
        if (!YTKACERecoveryStillCurrent(overlay, state)) {
            state->budget.finish();
            return;
        }
        if (ytkace::playbackAdvanced(savedTime, YTKACEPosition(current))) {
            state->budget.finish();
            return;
        }
        YTKACECaptionsSnapshot(current);
        if (!YTKACEReloadPlayer(current, @"bounded recovery")) {
            YTKACESendRetryEvent(overlay, @"bounded recovery");
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
            (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            id activeOverlay = weakReceiver;
            id activePlayer = state.player;
            if (!YTKACERecoveryStillCurrent(activeOverlay, state)) return;
            if (savedTime > 0 &&
                !ytkace::playbackAdvanced(savedTime, YTKACEPosition(activePlayer))) {
                YTKACESeek(activePlayer, savedTime, @"bounded recovery");
            }
            YTKACEScheduleCaptionRestore(activePlayer);
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
            (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            id activeOverlay = weakReceiver;
            id activePlayer = state.player;
            BOOL valid = YTKACERecoveryStillCurrent(activeOverlay, state);
            state->budget.finish();
            if (!valid) return;
            if (ytkace::playbackAdvanced(savedTime, YTKACEPosition(activePlayer))) {
                YTKACEDownloadLog(@"fix", @"native playback recovered");
                return;
            }
            // At most one further attempt; a persistent rejection restores the
            // native error instead of creating an unbounded reload loop.
            YTKACEHandleError(activeOverlay, selector, error);
        });
    });
}

void YTKACEInstallPlaybackFixHooks(void) {
    BOOL handle = YTKACEInstallInstanceHook(
        @"YTMainAppVideoPlayerOverlayViewController", @"handleError:",
        (IMP)YTKACEHandleError, &OriginalHandleError);
    YTKACEDownloadLog(@"fix", @"hooks handle=%d mode=%ld",
        handle, (long)YTKACEPlaybackFixMode());
}
