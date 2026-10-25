#import <UIKit/UIKit.h>
typedef NS_ENUM(NSInteger, YTKACESettingsTransferAction) {
    YTKACESettingsCopy, YTKACESettingsPaste, YTKACESettingsExport,
    YTKACESettingsImport, YTKACESettingsRestore
};
FOUNDATION_EXPORT void YTKACEPresentSettingsTransfer(UIViewController *controller,
                                                     YTKACESettingsTransferAction action);
