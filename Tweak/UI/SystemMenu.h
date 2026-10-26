#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// A rendered native row whose text is unavailable through public/object data.
// Borrow its live view for the list, then restore hierarchy/layout before the
// native owner closes. Selection still uses the verified action block.
@interface YTKACEMenuNativeRow : NSObject
@property(nonatomic, readonly) UIView *view;
@property(nonatomic, readonly) CGFloat height;
- (nullable instancetype)initWithView:(UIView *)view;
- (void)mountInView:(UIView *)host;
- (void)restore;
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
NS_ASSUME_NONNULL_END
