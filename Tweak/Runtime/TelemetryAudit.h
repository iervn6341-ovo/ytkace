#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Installs a passive NSURLSession audit hook. Recording remains off until the
/// user opts in through the Telemetry Audit settings page.
FOUNDATION_EXPORT void YTKACEInstallTelemetryAudit(void);
FOUNDATION_EXPORT BOOL YTKACETelemetryAuditEnabled(void);
FOUNDATION_EXPORT void YTKACESetTelemetryAuditEnabled(BOOL enabled);
FOUNDATION_EXPORT NSUInteger YTKACETelemetryAuditRecordCount(void);
FOUNDATION_EXPORT NSString *YTKACETelemetryAuditReportText(void);
FOUNDATION_EXPORT NSData *YTKACETelemetryAuditReportJSON(void);
FOUNDATION_EXPORT void YTKACEClearTelemetryAudit(void);

NS_ASSUME_NONNULL_END
