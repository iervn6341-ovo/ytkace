#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
// Register only a button created by a tweak. Native YouTube controls must never
// inherit menu conversion merely because they live in the player overlay.
FOUNDATION_EXPORT __attribute__((visibility("default"))) void YTKACERegisterTweakPlayerMenuSource(UIView *source);
FOUNDATION_EXPORT void YTKACERegisterNativeGearMenuSource(UIView *source);
FOUNDATION_EXPORT BOOL YTKACEIsNativeGearMenuSource(UIView *source);
FOUNDATION_EXPORT UIView * _Nullable YTKACEPlayerMenuSource(UIViewController *controller);
// Called for a new window touch, including controls using UIAction rather than
// sendAction:to:forEvent:. Only remembers registered tweak sources.
FOUNDATION_EXPORT void YTKACEUpdatePlayerMenuTouchSource(UIView * _Nullable target, UIWindow *window);
FOUNDATION_EXPORT BOOL YTKACEIsPlayerMenuSource(UIView * _Nullable source);
// Only for controllers whose content and dismissal lifecycle YTKACE owns.
FOUNDATION_EXPORT BOOL YTKACEConfigurePlayerPopover(UIViewController *controller,
    UIViewController *presenter, UIView * _Nullable source, CGSize size);
FOUNDATION_EXPORT BOOL YTKACEIsPlayerPopover(UIViewController *controller);
FOUNDATION_EXPORT void YTKACERememberPlayerMenuSource(UIView * _Nullable source);
FOUNDATION_EXPORT void YTKACEInstallPlayerMenuPresentation(void);
NS_ASSUME_NONNULL_END
