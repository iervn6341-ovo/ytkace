#import "TelemetryAudit.h"
#import "TelemetryRecord.h"

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
        [directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
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

static NSString *YTKACETelemetryTimestamp(void) {
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ formatter = [NSISO8601DateFormatter new]; });
    @synchronized (formatter) { return [formatter stringFromDate:NSDate.date]; }
}

static void YTKACERecordTelemetryRequest(NSURLRequest *request) {
    if (!request.URL.host.length) return;
    NSDictionary *snapshot = YTKACETelemetrySnapshot(request, YTKACETelemetryAuditDetailsEnabled());
    dispatch_async(YTKACETelemetryAuditQueue(), ^{
        NSDictionary *record = YTKACETelemetryFinalize(snapshot);
        NSData *encoded = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
        if (!encoded.length) return;
        NSURL *url = YTKACETelemetryAuditURL();
        NSMutableData *line = [encoded mutableCopy];
        [line appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
        if (![NSFileManager.defaultManager fileExistsAtPath:url.path]) {
            NSDictionary *attributes = @{};
#if TARGET_OS_IOS
            attributes = @{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication};
#endif
            [NSFileManager.defaultManager createFileAtPath:url.path contents:NSData.data attributes:attributes];
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:url error:nil];
        if (!handle) return;
        unsigned long long offset = 0;
        BOOL wrote = [handle seekToEndReturningOffset:&offset error:nil] && [handle writeData:line error:nil];
        [handle closeAndReturnError:nil];
        unsigned long long size = wrote ? offset + line.length : 0;
        if (size > YTKACETelemetryAuditLimit) {
            NSData *existing = [NSData dataWithContentsOfURL:url];
            NSUInteger keep = MIN(existing.length, YTKACETelemetryAuditLimit * 3 / 4);
            NSData *tail = [existing subdataWithRange:NSMakeRange(existing.length - keep, keep)];
            NSRange newline = [tail rangeOfData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding] options:0 range:NSMakeRange(0, tail.length)];
            if (newline.location != NSNotFound) tail = [tail subdataWithRange:NSMakeRange(NSMaxRange(newline), tail.length - NSMaxRange(newline))];
            [tail writeToURL:url atomically:YES];
        }
    });
}

static void YTKACETelemetryTaskResume(NSURLSessionTask *receiver, SEL selector) {
    @try {
        if (YTKACETelemetryAuditEnabled() &&
            objc_getAssociatedObject(receiver, YTKACETelemetryAuditTaskKey) == nil) {
            objc_setAssociatedObject(receiver, YTKACETelemetryAuditTaskKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSURLRequest *request = receiver.currentRequest ?: receiver.originalRequest;
            if (request != nil) YTKACERecordTelemetryRequest(request);
        }
    } @catch (__unused NSException *exception) { /* Observation must not prevent task execution. */ }
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

BOOL YTKACETelemetryAuditDetailsEnabled(void) {
    return YTKACEFeatureEnabled(@"YTKACE.Preference.Privacy.TelemetryAuditDetails");
}

void YTKACESetTelemetryAuditDetailsEnabled(BOOL enabled) {
    YTKACESetPreference(@"YTKACE.Preference.Privacy.TelemetryAuditDetails", enabled);
}

void YTKACELoadTelemetryAuditRecords(void (^completion)(NSArray<NSDictionary *> *records)) {
    dispatch_async(YTKACETelemetryAuditQueue(), ^{
        NSArray *records = YTKACETelemetryAuditRecordsLocked();
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(records); });
    });
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
        @"schemaVersion": @2,
        @"generatedAt": YTKACETelemetryTimestamp(),
        @"scope": @"Outbound NSURLSession tasks observed inside the YouTube process.",
        @"limitations": @[
            @"This is an observation log, not proof of what a remote server stores.",
            @"Requests sent through other networking stacks may not appear.",
            @"Metadata mode excludes paths, queries, header values and bodies. Optional details contain redacted path/query/header and bounded JSON previews; credentials and raw body bytes are excluded."
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
    [text appendString:@"Privacy\nMetadata only by default. Optional request details contain redacted path/query/header and bounded JSON previews. Raw body bytes and credentials are excluded.\n\n"];
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
        if ([record[@"detailsCaptured"] boolValue]) {
            NSData *detail = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
            if (detail) [text appendFormat:@"%@\n\n", [[NSString alloc] initWithData:detail encoding:NSUTF8StringEncoding]];
        }
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
