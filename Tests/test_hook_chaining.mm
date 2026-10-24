#import <Foundation/Foundation.h>
#import "../Tweak/Runtime/Hooking.h"
#import "../Tweak/Features/Downloads/DownloadLog.h"

#include <cassert>

// Runtime enumeration logging is irrelevant to selector-chain behavior.
void YTKACEDownloadLog(NSString *, NSString *, ...) {}

@interface YTKACEHookTest : NSObject
- (NSInteger)value;
+ (NSInteger)value;
@end
@implementation YTKACEHookTest
- (NSInteger)value { return 1; }
+ (NSInteger)value { return 2; }
@end

static IMP FirstOriginal, SecondOriginal, ClassFirstOriginal, ClassSecondOriginal;
static NSInteger First(id object, SEL selector) {
    return ((NSInteger (*)(id, SEL))FirstOriginal)(object, selector) + 10;
}
static NSInteger Second(id object, SEL selector) {
    return ((NSInteger (*)(id, SEL))SecondOriginal)(object, selector) + 100;
}
static NSInteger ClassFirst(id object, SEL selector) {
    return ((NSInteger (*)(id, SEL))ClassFirstOriginal)(object, selector) + 10;
}
static NSInteger ClassSecond(id object, SEL selector) {
    return ((NSInteger (*)(id, SEL))ClassSecondOriginal)(object, selector) + 100;
}

int main() {
    @autoreleasepool {
        assert(YTKACEInstallInstanceHook(@"YTKACEHookTest", @"value", (IMP)First, &FirstOriginal));
        assert(YTKACEInstallInstanceHook(@"YTKACEHookTest", @"value", (IMP)Second, &SecondOriginal));
        YTKACEHookTest *object = [YTKACEHookTest new];
        assert(object.value == 111);
        IMP repeatedOriginal = NULL;
        assert(YTKACEInstallInstanceHook(@"YTKACEHookTest", @"value", (IMP)First, &repeatedOriginal));
        assert(repeatedOriginal == FirstOriginal);
        assert(object.value == 111); // Reinstalling a buried hook cannot make a cycle.
        assert(YTKACEInstallClassHook(@"YTKACEHookTest", @"value", (IMP)ClassFirst, &ClassFirstOriginal));
        assert(YTKACEInstallClassHook(@"YTKACEHookTest", @"value", (IMP)ClassSecond, &ClassSecondOriginal));
        assert([YTKACEHookTest value] == 112);
        assert(!YTKACEInstallInstanceHook(@"YTKACEHookTest", @"missing", (IMP)First, NULL));
    }
}
