#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Explicit opt-in: no prefix-based access to YouTube's defaults or credentials.
// Rule fields: default (required), values, minimum, maximum, elementType, pattern.
FOUNDATION_EXPORT void YTKACERegisterSettingsModule(NSString *identifier,
                                                   NSDictionary<NSString *, NSDictionary *> *rules);
FOUNDATION_EXPORT NSDictionary *YTKACESettingsRule(id defaultValue);
FOUNDATION_EXPORT NSData * _Nullable YTKACEExportSettings(NSUserDefaults *defaults, NSError * _Nullable * _Nullable error);
// Returns only validated, registered keys. Unknown keys/modules are counted and skipped.
FOUNDATION_EXPORT NSDictionary * _Nullable YTKACEPreviewSettings(NSData *data, NSUInteger * _Nullable skipped,
                                                                  NSError * _Nullable * _Nullable error);
FOUNDATION_EXPORT BOOL YTKACEApplySettings(NSData *data, NSUserDefaults *defaults,
                                           NSURL *backupURL, NSError * _Nullable * _Nullable error);
NS_ASSUME_NONNULL_END
