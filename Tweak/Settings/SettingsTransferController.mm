#import "SettingsTransferController.h"
#import "YTKACESettingsPages.h"
#import "../Runtime/SettingsTransfer.h"
#import "../Runtime/Preferences.h"
#import "../Runtime/Localization.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

static const void *YTKACESettingsTransferAssociation = &YTKACESettingsTransferAssociation;

static void YTKACERegisterTransferRules(void) {
    NSDictionary *registered = [NSUserDefaults.standardUserDefaults volatileDomainForName:NSRegistrationDomain];
    NSMutableDictionary *rules = [NSMutableDictionary dictionary];
    for (NSDictionary *page in YTKACEAllPageDefinitions()) {
        for (NSArray *section in page[@"sections"]) for (NSDictionary *row in section) {
            NSString *key = row[@"key"];
            if (!key.length) continue;
            NSString *type = row[@"type"];
            id fallback = registered[key];
            NSMutableDictionary *rule = [NSMutableDictionary dictionary];
            if ([type isEqual:@"toggle"]) fallback = fallback ?: @NO;
            else if (row[@"values"]) {
                NSArray *values = row[@"values"];
                NSUInteger index = [row[@"default"] unsignedIntegerValue];
                fallback = fallback ?: (index < values.count ? values[index] : values.firstObject);
                rule[@"values"] = values;
            } else if ([type isEqual:@"color"]) {
                fallback = row[@"fallback"];
                rule[@"pattern"] = @"^#[0-9A-Fa-f]{6}$";
            } else if (row[@"minimum"] && row[@"maximum"]) {
                fallback = fallback ?: row[@"fallback"];
                rule[@"minimum"] = row[@"minimum"];
                rule[@"maximum"] = row[@"maximum"];
            }
            if (!fallback) continue;
            rule[@"default"] = fallback;
            rules[key] = rule;
        }
    }
    rules[@"YTKACE.Preference.Tabs.Names"] = YTKACESettingsRule(@{});
    rules[@"YTKACE.Preference.Tabs.Startup"] = YTKACESettingsRule(@"");
    // Tab editor keys are generated outside the declarative settings pages.
    for (NSString *tab in @[@"Home", @"Shorts", @"Subscriptions", @"Library", @"YTKACETab", @"Create",
                            @"Music", @"Live", @"Gaming", @"News", @"Posts", @"Sports", @"Learning",
                            @"Fashion", @"Playlists", @"History", @"Notifs", @"WatchLater"]) {
        NSString *key = [@"YTKACE.Preference.Tabs.Hidden." stringByAppendingString:tab];
        rules[key] = YTKACESettingsRule(registered[key] ?: @NO);
    }
    YTKACERegisterSettingsModule(@"YTKACE", rules);

    NSMutableDictionary *caption = [NSMutableDictionary dictionary];
    NSDictionary *captionDefaults = @{
        @"CaptionIsland.Enabled": @YES, @"CaptionIsland.ExternalLyricsEnabled": @YES,
        @"CaptionIsland.SourcePriority": @0, @"CaptionIsland.ShowSourceBadge": @YES,
        @"CaptionIsland.PreferredLanguage": @"zh-Hant",
        @"CaptionIsland.CaptionLanguagePriorities.v1": @[@"zh-Hant", @"en", @"ja"],
        @"CaptionIsland.DebugLogging": @NO, @"CaptionIsland.DisableForShorts": @YES,
        @"CaptionIsland.MaximumVideoDurationMinutes": @5, @"CaptionIsland.ReturnHomeMode": @0,
        @"CaptionIsland.PlayerButtonEnabled": @YES, @"CaptionIsland.GearMenuItemEnabled": @YES,
        @"CaptionIsland.DiscardedTitleKeywords": @[@"Official Music Video", @"Official Lyric Video",
            @"Official Video", @"Music Video", @"Lyric Video", @"Official Audio", @"Official Visualizer"],
        @"CaptionIsland.LRCLIBBaseURL": @"https://lrclib.net"
    };
    for (NSString *key in captionDefaults) caption[key] = YTKACESettingsRule(captionDefaults[key]);
    caption[@"CaptionIsland.SourcePriority"] = @{@"default": @0, @"values": @[@0, @1]};
    caption[@"CaptionIsland.ReturnHomeMode"] = @{@"default": @0, @"values": @[@0, @1]};
    caption[@"CaptionIsland.MaximumVideoDurationMinutes"] = @{@"default": @5, @"minimum": @0, @"maximum": @180};
    YTKACERegisterSettingsModule(@"CaptionIsland", caption);
    YTKACERegisterSettingsModule(@"PlayerButtons", @{
        @"YTVideoOverlay-YouQuality-Enabled": YTKACESettingsRule(@YES),
        @"YTVideoOverlay-YouQuality-Position": @{@"default": @0, @"values": @[@0, @1]},
        @"YTVideoOverlay-YouQuality-Order": @{@"default": @0, @"minimum": @0, @"maximum": @100},
        @"YTVideoOverlay-CaptionIslandLyrics-Order": @{@"default": @0, @"minimum": @0, @"maximum": @100},
        @"YTVideoOverlay-FrostedGlassBottom": YTKACESettingsRule(@NO)
    });
}

@interface YTKACESettingsTransferController : NSObject <UIDocumentPickerDelegate>
@property(nonatomic, weak) UIViewController *owner;
@property(nonatomic, strong) NSURL *exportDirectory;
- (void)perform:(YTKACESettingsTransferAction)action;
@end

@implementation YTKACESettingsTransferController
- (void)presentAlertWhenReady:(UIAlertController *)alert {
    UIViewController *owner = self.owner;
    if (!owner.view.window) return;
    UIViewController *presented = owner.presentedViewController;
    if (presented) {
        if (![presented isKindOfClass:UIDocumentPickerViewController.class] &&
            ![presented isKindOfClass:UIAlertController.class]) return;
        id<UIViewControllerTransitionCoordinator> transition = presented.transitionCoordinator;
        if (presented.isBeingDismissed && transition &&
            [transition animateAlongsideTransition:nil completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
                [self presentAlert:alert];
            }]) return;
        [owner dismissViewControllerAnimated:YES completion:^{ [self presentAlert:alert]; }];
        return;
    }
    [owner presentViewController:alert animated:YES completion:nil];
}
- (void)presentAlert:(UIAlertController *)alert {
    // Let UIKit start dismissing a picker/confirmation before showing the next alert.
    dispatch_async(dispatch_get_main_queue(), ^{ [self presentAlertWhenReady:alert]; });
}
- (NSURL *)backupURL {
    return [YTKACEApplicationSupportDirectory() URLByAppendingPathComponent:@"Settings-before-import.json"];
}
- (void)message:(NSString *)message detail:(NSString *)detail {
    UIViewController *owner = self.owner;
    if (!owner.view.window) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:YTKACELocalized(message)
        message:detail preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:YTKACELocalized(@"OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentAlert:alert];
}
- (void)preview:(NSData *)data {
    NSError *error = nil;
    NSUInteger skipped = 0;
    NSDictionary *changes = YTKACEPreviewSettings(data, &skipped, &error);
    if (!changes) { [self message:@"Settings Transfer Failed" detail:error.localizedDescription]; return; }
    NSUInteger changed = 0;
    for (NSString *key in changes) if (![[NSUserDefaults.standardUserDefaults objectForKey:key] isEqual:changes[key]]) ++changed;
    NSString *summary = [NSString stringWithFormat:YTKACELocalized(@"Import %lu settings (%lu changed). Skip %lu unknown entries. Restart YouTube after importing. A previous-settings snapshot is saved automatically."),
                        (unsigned long)changes.count, (unsigned long)changed, (unsigned long)skipped];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:YTKACELocalized(@"Paste / Import Settings")
        message:summary preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:YTKACELocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:YTKACELocalized(@"Import Settings") style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) {
            NSError *applyError = nil;
            if (YTKACEApplySettings(data, NSUserDefaults.standardUserDefaults, [self backupURL], &applyError)) {
                [self message:@"Settings Imported" detail:YTKACELocalized(@"Restart YouTube to apply all settings.")];
            } else [self message:@"Settings Transfer Failed" detail:applyError.localizedDescription];
        }]];
    [self presentAlert:alert];
}
- (void)perform:(YTKACESettingsTransferAction)action {
    if (action == YTKACESettingsPaste) {
        NSString *text = UIPasteboard.generalPasteboard.string;
        if (text.length > 1024 * 1024) {
            [self message:@"Settings Transfer Failed" detail:YTKACELocalized(@"Settings must be a JSON file smaller than 1 MB.")];
            return;
        }
        [self preview:[text dataUsingEncoding:NSUTF8StringEncoding] ?: NSData.data];
    } else if (action == YTKACESettingsRestore) {
        [self preview:[NSData dataWithContentsOfURL:[self backupURL]] ?: NSData.data];
    } else if (action == YTKACESettingsImport) {
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
            initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
        picker.delegate = self;
        [self.owner presentViewController:picker animated:YES completion:nil];
    } else {
        NSError *error = nil;
        NSData *data = YTKACEExportSettings(NSUserDefaults.standardUserDefaults, &error);
        if (!data) { [self message:@"Settings Transfer Failed" detail:error.localizedDescription]; return; }
        if (action == YTKACESettingsCopy) {
            UIPasteboard.generalPasteboard.string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            [self message:@"Settings Copied" detail:YTKACELocalized(@"Includes YTKACE, CaptionIsland, and player button settings. No account data or downloads.")];
        } else {
            NSURL *directory = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
            self.exportDirectory = [directory URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
            if (![NSFileManager.defaultManager createDirectoryAtURL:self.exportDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
                [self message:@"Settings Transfer Failed" detail:error.localizedDescription]; return;
            }
            NSURL *url = [self.exportDirectory URLByAppendingPathComponent:@"YTKACE-settings.json"];
            if (![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
                [self message:@"Settings Transfer Failed" detail:error.localizedDescription]; return;
            }
            UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[url] asCopy:YES];
            picker.delegate = self;
            [self.owner presentViewController:picker animated:YES completion:nil];
        }
    }
}
- (void)cleanExport {
    if (self.exportDirectory) [NSFileManager.defaultManager removeItemAtURL:self.exportDirectory error:nil];
    self.exportDirectory = nil;
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
    [self cleanExport];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    if (self.exportDirectory) { [self cleanExport]; return; }
    NSURL *url = urls.firstObject;
    if (!url) return;
    // File-provider reads and coordination must not block a player/menu transition.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL scoped = [url startAccessingSecurityScopedResource];
        __block NSData *data = nil;
        __block NSError *readError = nil;
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [coordinator coordinateReadingItemAtURL:url options:0 error:&readError byAccessor:^(NSURL *local) {
            NSNumber *size = nil;
            if (![local getResourceValue:&size forKey:NSURLFileSizeKey error:&readError] || size.unsignedLongLongValue > 1024 * 1024) return;
            data = [NSData dataWithContentsOfURL:local options:0 error:&readError];
        }];
        if (scoped) [url stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.owner.view.window) return;
            if (!data) [self message:@"Settings Transfer Failed" detail:readError.localizedDescription ?: YTKACELocalized(@"Settings must be a JSON file smaller than 1 MB.")];
            else [self preview:data];
        });
    });
}
@end

void YTKACEPresentSettingsTransfer(UIViewController *controller, YTKACESettingsTransferAction action) {
    YTKACERegisterTransferRules();
    YTKACESettingsTransferController *transfer = objc_getAssociatedObject(controller, YTKACESettingsTransferAssociation);
    if (!transfer) {
        transfer = [YTKACESettingsTransferController new];
        transfer.owner = controller;
        objc_setAssociatedObject(controller, YTKACESettingsTransferAssociation, transfer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [transfer perform:action];
}
