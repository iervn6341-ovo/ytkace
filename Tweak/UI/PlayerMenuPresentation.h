#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT BOOL YTKACEIsPlayerMenuSource(UIView * _Nullable source);
// Only for controllers whose content and dismissal lifecycle YTKACE owns.
FOUNDATION_EXPORT BOOL YTKACEConfigurePlayerPopover(UIViewController *controller,
    UIViewController *presenter, UIView * _Nullable source, CGSize size);
FOUNDATION_EXPORT BOOL YTKACEIsPlayerPopover(UIViewController *controller);
FOUNDATION_EXPORT void YTKACERememberPlayerMenuSource(UIView * _Nullable source);
FOUNDATION_EXPORT void YTKACEInstallPlayerMenuPresentation(void);
NS_ASSUME_NONNULL_END
