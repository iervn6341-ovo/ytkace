#import <Foundation/Foundation.h>
#import "../Tweak/Settings/CaptionIslandIntegration.h"
#import <dlfcn.h>
#include <cassert>

int main(int argc, const char **argv) {
    @autoreleasepool {
        assert(argc == 2);
        // No CaptionIsland dylib: no broken settings entry and no hard link dependency.
        assert(!YTKACEIntegratesCaptionIslandSettings());
        assert(YTKACEMakeCaptionIslandSettingsPage() == nil);
        void *library = dlopen(argv[1], RTLD_NOW | RTLD_GLOBAL);
        if (!library) fprintf(stderr, "%s\n", dlerror());
        assert(library);
        // Resolve on use: loading CaptionIsland after YTKACE must still add a working page.
        assert(YTKACEIntegratesCaptionIslandSettings());
        id page = YTKACEMakeCaptionIslandSettingsPage();
        assert([NSStringFromClass([page class]) isEqual:@"CITestCaptionSettingsController"]);
        puts("CaptionIsland settings bridge handles absent and late-loaded factories.");
    }
}
