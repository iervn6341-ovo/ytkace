#import <Foundation/Foundation.h>
@class UIViewController;
@interface CITestCaptionSettingsController : NSObject
@end
@implementation CITestCaptionSettingsController
@end
extern "C" UIViewController *CIMakeSettingsViewController(void) {
    return (UIViewController *)[CITestCaptionSettingsController new];
}
