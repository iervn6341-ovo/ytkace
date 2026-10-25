#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Snapshot never reads a body stream. Only bounded JSON data is temporarily held
// in memory until finalized on the audit queue; raw bytes never enter the log.
FOUNDATION_EXPORT NSDictionary *YTKACETelemetrySnapshot(NSURLRequest *request, BOOL details);
FOUNDATION_EXPORT NSDictionary *YTKACETelemetryFinalize(NSDictionary *snapshot);
NS_ASSUME_NONNULL_END
