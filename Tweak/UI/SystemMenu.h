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
// Refit multiline Auto Layout/native sizeThatFits content at the cell width.
- (CGFloat)heightForWidth:(CGFloat)width;
@property(nonatomic, strong) UIColor *disclosureColor;
- (nullable instancetype)initWithView:(UIView *)view;
// Keep a complete native selector interactive inside the shared menu shell.
- (nullable instancetype)initWithView:(UIView *)view interactive:(BOOL)interactive;
// A child controller root requires a matching UIKit containment handoff.
- (nullable instancetype)initWithContentController:(UIViewController *)controller;
@property(nonatomic, readonly) BOOL interactive;
- (void)mountInView:(UIView *)host;
- (void)mountInView:(UIView *)host controller:(UIViewController * _Nullable)controller;
- (void)restore;
// Freeze only the rendered row, while returning the live node to its owner.
- (void)captureRendering;
- (BOOL)preserveRendering;
@property(nonatomic, readonly) BOOL renderingAvailable;
@end
FOUNDATION_EXPORT void YTKACESetSystemMenuBackAction(UIViewController *presenter, dispatch_block_t _Nullable action);
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
FOUNDATION_EXPORT void YTKACEMarkSystemMenuSelected(UIViewController *menu);
FOUNDATION_EXPORT void YTKACENotifySystemMenuDismissed(UIViewController *menu);
// Preserve the outgoing popover while native owners change underneath it.
FOUNDATION_EXPORT void YTKACEBeginSystemMenuTransition(UIViewController *menu);
// Preserve reuse without showing a frozen cover for post-dismissal model actions.
FOUNDATION_EXPORT void YTKACERetainSystemMenuForNavigation(UIViewController *menu);
FOUNDATION_EXPORT id _Nullable YTKACESystemMenuTransitionToken(UIWindow *window, UIView *source);
FOUNDATION_EXPORT void YTKACECancelSystemMenuTransitionToken(id _Nullable token);
FOUNDATION_EXPORT void YTKACEContinueSystemMenuTransition(UIView *source);
FOUNDATION_EXPORT void YTKACECancelSystemMenuTransition(UIView *source);
NS_ASSUME_NONNULL_END
