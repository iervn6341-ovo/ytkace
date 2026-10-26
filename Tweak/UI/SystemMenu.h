#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// UIKit list: anchored player popover, settings sheet; original action callbacks.
FOUNDATION_EXPORT BOOL YTKACEPresentSystemMenu(UIViewController *presenter,
                                               UIView * _Nullable source,
                                               NSString * _Nullable title,
                                               NSString * _Nullable subtitle,
                                               NSArray<NSDictionary *> *actions);
// Bind before presentation, which UIKit may forward/defer. Called once for
// close/tap-outside as well as selection, after dismissal has completed.
FOUNDATION_EXPORT BOOL YTKACEPresentSystemMenuWithDismissal(UIViewController *presenter,
    UIView * _Nullable source, NSString * _Nullable title, NSString * _Nullable subtitle,
    NSArray<NSDictionary *> *actions, void (^ _Nullable handler)(BOOL selectedAction));
FOUNDATION_EXPORT void YTKACENotifySystemMenuDismissed(UIViewController *menu);
NS_ASSUME_NONNULL_END
