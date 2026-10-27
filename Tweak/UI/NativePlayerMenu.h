#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
// Builds an anchored UIKit list from a complete native action model. The caller
// still presents the native controller through its original UIKit lifecycle.
FOUNDATION_EXPORT NSArray<NSDictionary *> * _Nullable YTKACENativePlayerActions(UIViewController *controller);
FOUNDATION_EXPORT NSArray<NSDictionary *> * _Nullable YTKACENativePlayerRows(UIViewController *controller);
FOUNDATION_EXPORT void YTKACEPresentNativeGearMenu(UIViewController *controller, UIView *source);
FOUNDATION_EXPORT BOOL YTKACENativeMenuNeedsTextRetry(UIViewController *controller);
FOUNDATION_EXPORT void YTKACEEnableNativeMenuOutsideDismissal(UIViewController *controller);
FOUNDATION_EXPORT void YTKACEPresentAdaptedPlayerMenu(UIViewController *controller,
    UIView *source, NSArray<NSDictionary *> *actions);
FOUNDATION_EXPORT void YTKACEInstallNativePlayerMenuAdapter(void);
FOUNDATION_EXPORT NSString * _Nullable YTKACENativeControlTitle(UIView *source);
FOUNDATION_EXPORT BOOL YTKACEDeferNativeELMPresentation(UIViewController *presenter,
    UIViewController *presented, BOOL animated, void (^ _Nullable completion)(void));
// Diagnostic observers are scoped to one selected native action; no dispatch changes.
FOUNDATION_EXPORT void YTKACETraceNativeControlDispatch(UIControl *control, NSString *phase,
    NSString *kind, SEL _Nullable selector, id _Nullable target, BOOL hasEvent);
FOUNDATION_EXPORT void YTKACETraceNativePresentation(UIViewController *presenter, UIViewController *presented);
NS_ASSUME_NONNULL_END
