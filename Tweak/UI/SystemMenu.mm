#import "SystemMenu.h"
#import "../Runtime/Preferences.h"
#import "../Runtime/Localization.h"
#import <objc/message.h>

@interface YTKACESystemMenuController : UITableViewController
@property(nonatomic, copy) NSArray<NSDictionary *> *actions;
@property(nonatomic, copy) NSString *menuSubtitle;
@end

@implementation YTKACESystemMenuController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60.0;
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    SEL factory = NSSelectorFromString(@"effectWithStyle:");
    if (!UIAccessibilityIsReduceTransparencyEnabled() && [glassClass respondsToSelector:factory]) {
        UIVisualEffect *effect = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassClass, factory, 0);
        UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
        glass.userInteractionEnabled = NO;
        self.tableView.backgroundColor = UIColor.clearColor;
        self.tableView.backgroundView = glass;
    }
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeMenu)];
}
- (void)closeMenu { [self dismissViewControllerAnimated:YES completion:nil]; }
- (BOOL)accessibilityPerformEscape { [self closeMenu]; return YES; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; return self.actions.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section; return self.menuSubtitle.length ? self.menuSubtitle : nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SystemMenu"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SystemMenu"];
    NSDictionary *action = self.actions[indexPath.row];
    cell.textLabel.text = action[@"title"];
    NSMutableArray *details = [NSMutableArray array];
    for (NSString *key in @[@"subtitle", @"value"]) {
        NSString *detail = action[key];
        if (detail.length && ![details containsObject:detail]) [details addObject:detail];
    }
    cell.detailTextLabel.text = [details componentsJoinedByString:@"\n"];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.imageView.image = action[@"icon"];
    cell.accessoryType = [action[@"selected"] boolValue] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    if (action[@"secondary"] && ![action[@"selected"] boolValue]) {
        UIImageView *secondary = [[UIImageView alloc] initWithImage:action[@"secondary"]];
        secondary.contentMode = UIViewContentModeScaleAspectFit;
        secondary.frame = CGRectMake(0, 0, 22, 22);
        cell.accessoryView = secondary;
    }
    BOOL enabled = !action[@"enabled"] || [action[@"enabled"] boolValue];
    cell.userInteractionEnabled = enabled;
    cell.textLabel.textColor = !enabled ? UIColor.tertiaryLabelColor :
        ([action[@"destructive"] boolValue] ? UIColor.systemRedColor : UIColor.labelColor);
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessibilityTraits = UIAccessibilityTraitButton | (enabled ? 0 : UIAccessibilityTraitNotEnabled) |
        ([action[@"selected"] boolValue] ? UIAccessibilityTraitSelected : 0);
    cell.backgroundColor = UIColor.clearColor;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *action = self.actions[indexPath.row];
    if (action[@"enabled"] && ![action[@"enabled"] boolValue]) return;
    dispatch_block_t handler = action[@"handler"];
    // Dismiss before invoking actions which may immediately open another controller.
    // One presentation animation is enough for a submenu transition.
    [self dismissViewControllerAnimated:NO completion:^{ if (handler) handler(); }];
}
@end

BOOL YTKACEPresentSystemMenu(UIViewController *presenter, UIView *source,
                             NSString *title, NSString *subtitle,
                             NSArray<NSDictionary *> *actions) {
    if (![presenter isKindOfClass:UIViewController.class] ||
        !YTKACEFeatureEnabled(@"YTKACE.Preference.Interface.SystemMenus") ||
        !presenter.view.window || presenter.presentedViewController || actions.count == 0) return NO;
    for (NSDictionary *action in actions) {
        if (![action[@"title"] isKindOfClass:NSString.class] || ![action[@"title"] length]) return NO;
    }
    YTKACESystemMenuController *controller = [[YTKACESystemMenuController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    controller.title = title.length ? title : YTKACELocalized(@"Options");
    controller.menuSubtitle = subtitle;
    controller.actions = actions;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    navigation.view.backgroundColor = UIColor.clearColor;
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    if (presenter.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        navigation.modalPresentationStyle = UIModalPresentationPopover;
        navigation.preferredContentSize = CGSizeMake(360.0, MIN(600.0, 100.0 + actions.count * 64.0));
        UIPopoverPresentationController *popover = navigation.popoverPresentationController;
        popover.sourceView = source.window == presenter.view.window ? source : presenter.view;
        popover.sourceRect = popover.sourceView.bounds;
    } else {
        UISheetPresentationController *sheet = navigation.sheetPresentationController;
        sheet.prefersGrabberVisible = YES;
        sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
        if (@available(iOS 16.0, *)) {
            CGFloat height = MAX(240.0, 100.0 + actions.count * 64.0);
            sheet.detents = @[[UISheetPresentationControllerDetent customDetentWithIdentifier:@"YTKACE.Menu"
                resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                    return MIN(height, context.maximumDetentValue * 0.85);
                }], UISheetPresentationControllerDetent.largeDetent];
        } else sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
    }
    [presenter presentViewController:navigation animated:YES completion:nil];
    return YES;
}
