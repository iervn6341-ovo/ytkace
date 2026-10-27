#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSNotificationName const YTKACEPlayerMenuWillSelectAction;
FOUNDATION_EXPORT NSNotificationName const YTKACEPlayerMenuTouchSource;
// A rendered native row whose text is unavailable through public/object data.
// Borrow its live view for the list, then restore hierarchy/layout before the
// native owner closes. Selection still uses the verified action block.
@interface YTKACEMenuNativeRow : NSObject
@property(nonatomic, readonly) UIView *view;
@property(nonatomic, readonly) CGFloat height;
@property(nonatomic, strong) UIColor *disclosureColor;
- (nullable instancetype)initWithView:(UIView *)view;
- (void)mountInView:(UIView *)host;
- (void)restore;
// Freeze only the rendered row, while returning the live node to its owner.
- (void)captureRendering;
- (BOOL)preserveRendering;
@end
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
// Preserve the outgoing popover while native owners change underneath it.
FOUNDATION_EXPORT void YTKACEContinueSystemMenuTransition(UIView *source);
FOUNDATION_EXPORT void YTKACECancelSystemMenuTransition(UIView *source);
NS_ASSUME_NONNULL_END
