#import <Foundation/Foundation.h>
#import "../Tweak/Runtime/TelemetryRecord.h"
#include <cassert>

static NSString *Encode(NSDictionary *record) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
    assert(data);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}
@interface AuditSentinelStream : NSInputStream
@property(nonatomic) NSUInteger reads;
@end
@implementation AuditSentinelStream
- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len { (void)buffer; (void)len; ++self.reads; return 0; }
- (void)open { ++self.reads; }
@end

int main() {
    @autoreleasepool {
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:
            @"https://urluser:urlpassword@www.youtube.com/youtubei/v1/player?key=query-secret&videoId=watch-secret#fragment-secret"]];
        request.HTTPMethod = @"POST";
        [request setValue:@"Bearer auth-secret" forHTTPHeaderField:@"Authorization"];
        [request setValue:@"SID=cookie-secret" forHTTPHeaderField:@"Cookie"];
        [request setValue:@"custom-header-secret" forHTTPHeaderField:@"X-Custom"];
        [request setValue:@"application/json; boundary=boundary-secret" forHTTPHeaderField:@"Content-Type"];
        [request setValue:@"21.42.4" forHTTPHeaderField:@"X-Youtube-Client-Version"];
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{
            @"context": @{@"client": @{@"clientName": @"IOS", @"clientVersion": @"21.42.4",
                @"hl": @"zh-Hant", @"gl": @"TW", @"visitorData": @"visitor-secret",
                @"userAgent": @"agent-secret", @"screenWidthPoints": @414},
                @"user": @{@"email": @"email-secret@example.com", @"accountId": @"account-secret"}},
            @"videoId": @"video-secret", @"trackingParams": @"tracking-secret",
            @"nested": @[@{@"token": @"nested-token-secret", @"unknown": @"unknown-secret"}],
            @"contentCheckOk": @YES
        } options:0 error:nil];
        NSData *beforeBody = request.HTTPBody;
        NSDictionary *beforeHeaders = request.allHTTPHeaderFields;
        NSDictionary *metadata = YTKACETelemetryFinalize(YTKACETelemetrySnapshot(request, NO));
        assert(!metadata[@"headers"] && !metadata[@"pathPreview"] && !metadata[@"bodyPreview"]);
        assert([metadata[@"bodyBytes"] unsignedIntegerValue] == beforeBody.length);
        assert([metadata[@"service"] isEqual:@"Google / YouTube"]);
        assert([metadata[@"headerClasses"] containsObject:@"cookies"]);

        NSDictionary *details = YTKACETelemetryFinalize(YTKACETelemetrySnapshot(request, YES));
        NSString *encoded = Encode(details);
        for (NSString *secret in @[@"urluser", @"urlpassword", @"query-secret", @"watch-secret", @"fragment-secret",
            @"auth-secret", @"cookie-secret", @"custom-header-secret", @"boundary-secret", @"visitor-secret",
            @"agent-secret", @"email-secret", @"account-secret", @"video-secret", @"tracking-secret",
            @"nested-token-secret", @"unknown-secret"]) assert(![encoded containsString:secret]);
        assert([details[@"pathPreview"] isEqual:@"/youtubei/v1/player"]);
        assert([details[@"queryParameters"] count] == 2);
        assert([details[@"bodyPreview"] containsString:@"21.42.4"] && [details[@"bodyPreview"] containsString:@"414"]);
        assert([details[@"bodyPreview"] containsString:@"[redacted]"]);
        assert(!details[@"pendingBody"] && !details[@"observedAt"] && details[@"timestamp"]);
        assert([request.HTTPBody isEqual:beforeBody] && [request.allHTTPHeaderFields isEqual:beforeHeaders]);

        request.URL = [NSURL URLWithString:@"https://notgoogle.com/channel/channel-secret/watch-secret"];
        NSDictionary *other = YTKACETelemetryFinalize(YTKACETelemetrySnapshot(request, YES));
        assert([other[@"service"] isEqual:@"Other"] && ![Encode(other) containsString:@"channel-secret"]);
        request.URL = [NSURL URLWithString:@"https://sub.googleapis.com/api/search"];
        assert([YTKACETelemetryFinalize(YTKACETelemetrySnapshot(request, NO))[@"service"] isEqual:@"Google / YouTube"]);

        request.HTTPBody = [@"token=non-json-secret" dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *nonJSON = YTKACETelemetryFinalize(YTKACETelemetrySnapshot(request, YES));
        assert(!nonJSON[@"bodyPreview"] && ![Encode(nonJSON) containsString:@"non-json-secret"]);
        [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
        assert(!YTKACETelemetrySnapshot(request, YES)[@"pendingBody"]);
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [request setValue:@"gzip" forHTTPHeaderField:@"Content-Encoding"];
        assert(!YTKACETelemetrySnapshot(request, YES)[@"pendingBody"]);
        [request setValue:nil forHTTPHeaderField:@"Content-Encoding"];
        request.HTTPBody = [NSMutableData dataWithLength:32 * 1024 + 1];
        NSDictionary *largeSnapshot = YTKACETelemetrySnapshot(request, YES);
        assert(!largeSnapshot[@"pendingBody"]);
        assert(!YTKACETelemetryFinalize(largeSnapshot)[@"bodyPreview"]);
        request.HTTPBody = nil;
        AuditSentinelStream *stream = [AuditSentinelStream new];
        request.HTTPBodyStream = stream;
        NSDictionary *streamed = YTKACETelemetryFinalize(YTKACETelemetrySnapshot(request, YES));
        assert(stream.reads == 0 && ![streamed[@"bodySizeKnown"] boolValue] && !streamed[@"bodyPreview"]);
        assert([streamed[@"bodySource"] containsString:@"unknown"]);

        // Bounded traversal for deep or wide JSON; every persisted record stays JSON serializable.
        request.HTTPBodyStream = nil;
        id deep = @{@"token": @"deep-secret"};
        for (int i = 0; i < 30; ++i) deep = @{@"nested": deep};
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:deep options:0 error:nil];
        NSDictionary *bounded = YTKACETelemetryFinalize(YTKACETelemetrySnapshot(request, YES));
        assert(![Encode(bounded) containsString:@"deep-secret"]);
        assert([bounded[@"bodyPreview"] length] < 8192);
        puts("Telemetry records preserve metadata, redact credentials, bound previews, and never consume streams.");
    }
}
