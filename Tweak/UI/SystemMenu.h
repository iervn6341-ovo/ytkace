#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// UIKit list sheet/popover; action dictionaries retain their original callbacks.
FOUNDATION_EXPORT BOOL YTKACEPresentSystemMenu(UIViewController *presenter,
                                               UIView * _Nullable source,
                                               NSString * _Nullable title,
                                               NSString * _Nullable subtitle,
                                               NSArray<NSDictionary *> *actions);
NS_ASSUME_NONNULL_END
