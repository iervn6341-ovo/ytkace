#import "CaptionIslandIntegration.h"
#import <dlfcn.h>
typedef UIViewController *(*YTKACECaptionSettingsFactory)(void);
static YTKACECaptionSettingsFactory YTKACECaptionFactory(void) {
    return (YTKACECaptionSettingsFactory)dlsym(RTLD_DEFAULT, "CIMakeSettingsViewController");
}
BOOL YTKACEIntegratesCaptionIslandSettings(void) { return YTKACECaptionFactory() != NULL; }
UIViewController *YTKACEMakeCaptionIslandSettingsPage(void) {
    YTKACECaptionSettingsFactory factory = YTKACECaptionFactory();
    return factory ? factory() : nil;
}
