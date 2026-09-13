#import "TelemetryAudit.h"

#import "Hooking.h"
#import "Preferences.h"

#import <objc/runtime.h>

static const NSUInteger YTKACETelemetryAuditLimit = 768 * 1024;
static const void *YTKACETelemetryAuditTaskKey = &YTKACETelemetryAuditTaskKey;
static IMP OriginalNSURLSessionTaskResume;

static dispatch_queue_t YTKACETelemetryAuditQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.ytkace.telemetry-audit",
                                      DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSURL *YTKACETelemetryAuditURL(void) {
    static NSURL *URL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *directory = [YTKACEApplicationSupportDirectory()
            URLByAppendingPathComponent:@"TelemetryAudit" isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:directory
                               withIntermediateDirectories:YES
                                                attributes:nil error:nil];
        URL = [directory URLByAppendingPathComponent:@"outbound.ndjson"];
    });
    return URL;
}

static NSArray<NSDictionary *> *YTKACETelemetryAuditRecordsLocked(void) {
    NSData *data = [NSData dataWithContentsOfURL:YTKACETelemetryAuditURL()];
    if (data.length == 0) return @[];
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (text.length == 0) return @[];
    NSMutableArray<NSDictionary *> *records = [NSMutableArray array];
    [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        (void)stop;
        NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
        id value = lineData == nil ? nil :
            [NSJSONSerialization JSONObjectWithData:lineData options:0 error:nil];
        if ([value isKindOfClass:NSDictionary.class]) [records addObject:value];
    }];
    return records;
}

static NSString *YTKACETelemetryServiceForHost(NSString *host) {
    NSString *value = host.lowercaseString;
    if ([value hasSuffix:@"youtube.com"] || [value hasSuffix:@"youtubei.googleapis.com"] ||
        [value hasSuffix:@"googlevideo.com"] || [value hasSuffix:@"googleapis.com"] ||
        [value hasSuffix:@"google.com"] || [value hasSuffix:@"gstatic.com"] ||
        [value hasSuffix:@"ggpht.com"]) {
        return @"Google / YouTube";
    }
    if ([value isEqualToString:@"sponsor.ajay.app"]) return @"SponsorBlock";
    if ([value isEqualToString:@"dearrow-thumb.ajay.app"]) return @"DeArrow";
    return @"Other";
}

static NSArray<NSString *> *YTKACETelemetryHeaderClasses(NSDictionary *headers) {
    NSMutableOrderedSet<NSString *> *classes = [NSMutableOrderedSet orderedSet];
    for (id rawKey in headers) {
        if (![rawKey isKindOfClass:NSString.class]) continue;
        NSString *key = [rawKey lowercaseString];
        if ([key containsString:@"authorization"] || [key containsString:@"identity"] ||
            [key containsString:@"authuser"]) {
            [classes addObject:@"authentication"];
        } else if ([key isEqualToString:@"cookie"] || [key isEqualToString:@"set-cookie"]) {
            [classes addObject:@"cookies"];
        } else if ([key containsString:@"language"] || [key containsString:@"locale"]) {
            [classes addObject:@"locale"];
        } else if ([key containsString:@"client"] || [key containsString:@"version"] ||
                   [key containsString:@"visitor"] || [key isEqualToString:@"user-agent"]) {
            [classes addObject:@"client metadata"];
        } else {
            [classes addObject:@"other headers"];
        }
    }
    return classes.array;
}

static NSString *YTKACETelemetryTimestamp(void) {
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ formatter = [NSISO8601DateFormatter new]; });
    return [formatter stringFromDate:NSDate.date];
}

static void YTKACERecordTelemetryRequest(NSURLRequest *request) {
    NSURL *URL = request.URL;
    NSString *host = URL.host.lowercaseString;
    if (host.length == 0) return;
    NSDictionary *record = @{
        @"timestamp": YTKACETelemetryTimestamp(),
        @"host": host,
        @"service": YTKACETelemetryServiceForHost(host),
        @"method": request.HTTPMethod.uppercaseString ?: @"GET",
        @"bodyBytes": @(request.HTTPBody.length),
        @"headerClasses": YTKACETelemetryHeaderClasses(request.allHTTPHeaderFields ?: @{})
    };
    NSData *encoded = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
    if (encoded.length == 0) return;
    dispatch_async(YTKACETelemetryAuditQueue(), ^{
        NSURL *URL = YTKACETelemetryAuditURL();
        NSData *existing = [NSData dataWithContentsOfURL:URL] ?: NSData.data;
        NSMutableData *updated = [existing mutableCopy];
        [updated appendData:encoded];
        [updated appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
        if (updated.length > YTKACETelemetryAuditLimit) {
            NSUInteger keep = YTKACETelemetryAuditLimit * 3 / 4;
            NSData *tail = [updated subdataWithRange:
                NSMakeRange(updated.length - keep, keep)];
            NSRange firstNewline = [tail rangeOfData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]
                                             options:0 range:NSMakeRange(0, tail.length)];
            if (firstNewline.location != NSNotFound) {
                tail = [tail subdataWithRange:NSMakeRange(NSMaxRange(firstNewline),
                                                          tail.length - NSMaxRange(firstNewline))];
            }
            updated = [tail mutableCopy];
        }
        [updated writeToURL:URL atomically:YES];
    });
}

static void YTKACETelemetryTaskResume(NSURLSessionTask *receiver, SEL selector) {
    if (YTKACETelemetryAuditEnabled() &&
        objc_getAssociatedObject(receiver, YTKACETelemetryAuditTaskKey) == nil) {
        objc_setAssociatedObject(receiver, YTKACETelemetryAuditTaskKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSURLRequest *request = receiver.currentRequest ?: receiver.originalRequest;
        if (request != nil) YTKACERecordTelemetryRequest(request);
    }
    if (OriginalNSURLSessionTaskResume != NULL) {
        ((void (*)(id, SEL))OriginalNSURLSessionTaskResume)(receiver, selector);
    }
}

BOOL YTKACETelemetryAuditEnabled(void) {
    return YTKACEFeatureEnabled(YTKACETelemetryAuditKey);
}

void YTKACESetTelemetryAuditEnabled(BOOL enabled) {
    YTKACESetPreference(YTKACETelemetryAuditKey, enabled);
}

NSUInteger YTKACETelemetryAuditRecordCount(void) {
    __block NSUInteger count = 0;
    dispatch_sync(YTKACETelemetryAuditQueue(), ^{
        count = YTKACETelemetryAuditRecordsLocked().count;
    });
    return count;
}

static NSDictionary *YTKACETelemetryAuditReport(void) {
    __block NSArray<NSDictionary *> *records;
    dispatch_sync(YTKACETelemetryAuditQueue(), ^{
        records = YTKACETelemetryAuditRecordsLocked();
    });
    NSMutableDictionary<NSString *, NSNumber *> *services = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *hosts = [NSMutableDictionary dictionary];
    for (NSDictionary *record in records) {
        NSString *service = record[@"service"] ?: @"Other";
        NSString *host = record[@"host"] ?: @"unknown";
        services[service] = @([services[service] unsignedIntegerValue] + 1);
        hosts[host] = @([hosts[host] unsignedIntegerValue] + 1);
    }
    return @{
        @"schemaVersion": @1,
        @"generatedAt": YTKACETelemetryTimestamp(),
        @"scope": @"Outbound NSURLSession tasks observed inside the YouTube process.",
        @"limitations": @[
            @"This is an observation log, not proof of what a remote server stores.",
            @"Requests sent through other networking stacks may not appear.",
            @"URL paths and queries, header values, cookies, credentials, and request bodies are never recorded."
        ],
        @"summary": @{
            @"observedRequests": @(records.count),
            @"byService": services,
            @"byHost": hosts
        },
        @"records": records
    };
}

NSData *YTKACETelemetryAuditReportJSON(void) {
    return [NSJSONSerialization dataWithJSONObject:YTKACETelemetryAuditReport()
                                            options:NSJSONWritingPrettyPrinted error:nil] ?: NSData.data;
}

NSString *YTKACETelemetryAuditReportText(void) {
    NSDictionary *report = YTKACETelemetryAuditReport();
    NSDictionary *summary = report[@"summary"];
    NSMutableString *text = [NSMutableString stringWithFormat:
        @"YTKACE Telemetry Audit\nGenerated: %@\nObserved requests: %@\n\n",
        report[@"generatedAt"], summary[@"observedRequests"]];
    [text appendString:@"Scope\nOutbound NSURLSession tasks observed inside the YouTube process.\n\n"];
    [text appendString:@"Privacy\nNo URL paths or queries, header values, cookies, credentials, or request bodies are recorded.\n\n"];
    [text appendString:@"Requests by service\n"];
    NSDictionary *services = summary[@"byService"];
    for (NSString *service in [services.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
        [text appendFormat:@"- %@: %@\n", service, services[service]];
    }
    [text appendString:@"\nObserved requests\n"];
    for (NSDictionary *record in report[@"records"]) {
        NSString *headers = [record[@"headerClasses"] componentsJoinedByString:@", "];
        [text appendFormat:@"%@ | %@ | %@ | %@ | %@ bytes | %@\n",
            record[@"timestamp"], record[@"service"], record[@"host"],
            record[@"method"], record[@"bodyBytes"], headers.length == 0 ? @"no headers" : headers];
    }
    return text;
}

void YTKACEClearTelemetryAudit(void) {
    dispatch_sync(YTKACETelemetryAuditQueue(), ^{
        [NSFileManager.defaultManager removeItemAtURL:YTKACETelemetryAuditURL() error:nil];
    });
}

void YTKACEInstallTelemetryAudit(void) {
    YTKACEInstallInstanceHook(@"NSURLSessionTask", @"resume",
                              (IMP)YTKACETelemetryTaskResume,
                              &OriginalNSURLSessionTaskResume);
}
