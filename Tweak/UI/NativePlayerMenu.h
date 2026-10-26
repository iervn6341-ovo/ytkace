#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
// Builds an anchored UIKit list from a complete native action model. The caller
// still presents the native controller through its original UIKit lifecycle.
FOUNDATION_EXPORT NSArray<NSDictionary *> * _Nullable YTKACENativePlayerActions(UIViewController *controller);
FOUNDATION_EXPORT void YTKACEPresentAdaptedPlayerMenu(UIViewController *controller,
    UIView *source, NSArray<NSDictionary *> *actions);
FOUNDATION_EXPORT void YTKACEInstallNativePlayerMenuAdapter(void);
NS_ASSUME_NONNULL_END
