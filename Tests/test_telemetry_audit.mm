#import <Foundation/Foundation.h>
#import "../Tweak/Runtime/TelemetryAudit.h"
#import "../Tweak/Runtime/Preferences.h"
#import "../Tweak/Runtime/Hooking.h"
#include <cassert>

NSString *const YTKACETelemetryAuditKey = @"test.audit";
static NSURL *Directory;
static BOOL Recording, Details;
static IMP ResumeHook;
static NSUInteger Resumes;
BOOL YTKACEFeatureEnabled(NSString *key) { return [key isEqual:YTKACETelemetryAuditKey] ? Recording : Details; }
void YTKACESetPreference(NSString *key, BOOL value) {
    if ([key isEqual:YTKACETelemetryAuditKey]) Recording = value; else Details = value;
}
NSURL *YTKACEApplicationSupportDirectory(void) { return Directory; }
static void OriginalResume(id object, SEL selector) { (void)object; (void)selector; ++Resumes; }
BOOL YTKACEInstallInstanceHook(NSString *cls, NSString *name, IMP replacement, IMP *original) {
    assert([cls isEqual:@"NSURLSessionTask"] && [name isEqual:@"resume"]);
    ResumeHook = replacement;
    *original = (IMP)OriginalResume;
    return YES;
}
@interface AuditTaskFixture : NSObject
@property(nonatomic, strong) NSURLRequest *currentRequest;
@property(nonatomic, strong) NSURLRequest *originalRequest;
@property(nonatomic) BOOL broken;
@end
@implementation AuditTaskFixture
- (NSURLRequest *)currentRequest {
    if (self.broken) [NSException raise:@"FixtureFailure" format:@"request getter failed"];
    return _currentRequest;
}
@end
static AuditTaskFixture *Task(NSURLRequest *request) {
    AuditTaskFixture *task = [AuditTaskFixture new];
    task.currentRequest = request;
    return task;
}
static void Resume(AuditTaskFixture *task) { ((void (*)(id, SEL))ResumeHook)(task, NSSelectorFromString(@"resume")); }
static NSDictionary *Report(void) {
    return [NSJSONSerialization JSONObjectWithData:YTKACETelemetryAuditReportJSON() options:0 error:nil];
}

int main() {
    @autoreleasepool {
        Directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
        YTKACEInstallTelemetryAudit();
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://youtubei.googleapis.com/youtubei/v1/player?key=query-stub-secret"]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [@"{\"context\":{\"client\":{\"clientName\":\"IOS\",\"clientVersion\":\"21.42.4\"}},\"token\":\"body-stub-secret\"}" dataUsingEncoding:NSUTF8StringEncoding];
        [request setValue:@"Bearer header-stub-secret" forHTTPHeaderField:@"Authorization"];
        Resume(Task(request));
        assert(Resumes == 1 && YTKACETelemetryAuditRecordCount() == 0);
        YTKACESetTelemetryAuditEnabled(YES);
        AuditTaskFixture *task = Task(request);
        Resume(task); Resume(task);
        assert(Resumes == 3 && YTKACETelemetryAuditRecordCount() == 1);
        assert(![Report()[@"records"][0][@"detailsCaptured"] boolValue]);
        YTKACESetTelemetryAuditDetailsEnabled(YES);
        Resume(Task(request));
        NSDictionary *report = Report();
        assert([report[@"schemaVersion"] isEqual:@2] && [report[@"records"] count] == 2);
        assert([report[@"records"][1][@"bodyPreview"] containsString:@"21.42.4"]);
        NSString *json = [[NSString alloc] initWithData:YTKACETelemetryAuditReportJSON() encoding:NSUTF8StringEncoding];
        for (NSString *secret in @[@"query-stub-secret", @"body-stub-secret", @"header-stub-secret"]) assert(![json containsString:secret]);
        AuditTaskFixture *broken = [AuditTaskFixture new]; broken.broken = YES;
        Resume(broken);
        assert(Resumes == 5 && YTKACETelemetryAuditRecordCount() == 2);
        // Append enough records to exercise pruning; reports must remain valid after rotation.
        YTKACESetTelemetryAuditDetailsEnabled(NO);
        for (NSUInteger i = 0; i < 4000; ++i) { @autoreleasepool { Resume(Task(request)); } }
        report = Report();
        NSUInteger count = [report[@"records"] count];
        assert(count > 0 && count < 4002);
        NSURL *log = [Directory URLByAppendingPathComponent:@"TelemetryAudit/outbound.ndjson"];
        NSData *data = [NSData dataWithContentsOfURL:log];
        assert(data.length <= 768 * 1024);
        assert([report[@"summary"][@"observedRequests"] unsignedIntegerValue] == count);
        __block BOOL loaded = NO;
        YTKACELoadTelemetryAuditRecords(^(NSArray<NSDictionary *> *records) {
            assert(NSThread.isMainThread && records.count == count);
            loaded = YES;
        });
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
        while (!loaded && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        assert(loaded);
        YTKACEClearTelemetryAudit();
        assert(YTKACETelemetryAuditRecordCount() == 0);
        [NSFileManager.defaultManager removeItemAtURL:Directory error:nil];
        puts("Audit pipeline preserves resume, deduplicates tasks, redacts reports, rotates logs, loads asynchronously, and clears data.");
    }
}
