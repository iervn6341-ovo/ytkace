#import <Foundation/Foundation.h>
#import "../Tweak/Runtime/SettingsTransfer.h"
#include <cassert>

static NSData *Document(NSDictionary *modules, id version = @1) {
    return [NSJSONSerialization dataWithJSONObject:@{
        @"format": @"YTKACE.Settings", @"version": version, @"modules": modules
    } options:0 error:nil];
}

int main() {
    @autoreleasepool {
        NSString *suite = [@"YTKACE.Transfer.Tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
        assert([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil]);
        NSURL *backup = [directory URLByAppendingPathComponent:@"backup.json"];
        YTKACERegisterSettingsModule(@"Test", @{
            @"test.bool": YTKACESettingsRule(@YES),
            @"test.rate": @{@"default": @1.0, @"minimum": @0.25, @"maximum": @4.0},
            @"test.choice": @{@"default": @0, @"values": @[@0, @1, @2]},
            @"test.array": YTKACESettingsRule(@[@"en", @"zh-Hant"]),
            @"test.names": YTKACESettingsRule(@{}),
            @"test.color": @{@"default": @"#123ABC", @"pattern": @"^#[0-9A-Fa-f]{6}$"}
        });
        YTKACERegisterSettingsModule(@"CaptionIsland", @{@"CaptionIsland.Enabled": YTKACESettingsRule(@YES)});
        [defaults setObject:@"secret" forKey:@"YouTube.authToken"];
        [defaults setBool:NO forKey:@"test.bool"];
        NSError *error = nil;
        NSData *exported = YTKACEExportSettings(defaults, &error);
        assert(exported && !error);
        NSString *text = [[NSString alloc] initWithData:exported encoding:NSUTF8StringEncoding];
        assert(![text containsString:@"secret"] && ![text containsString:@"YouTube.authToken"]);
        NSDictionary *preview = YTKACEPreviewSettings(exported, NULL, &error);
        assert(preview.count == 7 && [preview[@"test.bool"] isEqual:@NO]);
        assert([preview[@"test.rate"] isEqual:@1.0]);

        NSData *valid = Document(@{@"Test": @{@"test.bool": @YES, @"test.rate": @2.5,
            @"test.array": @[@"ja", @"en"], @"test.names": @{@"home": @"首頁"}},
            @"CaptionIsland": @{@"CaptionIsland.Enabled": @NO}});
        assert(YTKACEApplySettings(valid, defaults, backup, &error));
        assert([defaults boolForKey:@"test.bool"] && [defaults doubleForKey:@"test.rate"] == 2.5);
        assert(![defaults boolForKey:@"CaptionIsland.Enabled"]);
        assert([[defaults stringForKey:@"YouTube.authToken"] isEqual:@"secret"]);
        NSData *snapshot = [NSData dataWithContentsOfURL:backup];
        assert(YTKACEApplySettings(snapshot, defaults, backup, &error));
        assert(![defaults boolForKey:@"test.bool"] && [defaults doubleForKey:@"test.rate"] == 1);

        NSUInteger skipped = 0;
        NSDictionary *known = YTKACEPreviewSettings(Document(@{@"Test": @{
            @"test.bool": @YES, @"YouTube.authToken": @"injected"}, @"Future": @{@"new": @1}}), &skipped, &error);
        assert(known.count == 1 && skipped == 2);
        // A second module cannot claim another module's key.
        YTKACERegisterSettingsModule(@"Other", @{@"test.bool": YTKACESettingsRule(@YES)});
        assert(!YTKACEPreviewSettings(Document(@{@"Other": @{@"test.bool": @YES}}), NULL, &error));

        NSArray *invalidSettings = @[
            @{@"test.bool": @"true"}, @{@"test.bool": @1}, @{@"test.rate": @YES},
            @{@"test.rate": @10}, @{@"test.choice": @3}, @{@"test.array": @[@1]},
            @{@"test.names": @{@"home": @[@"bad"]}}, @{@"test.color": @"bad"},
            @{@"test.bool": NSNull.null}, @{@"test.rate": @"2.5"}
        ];
        for (NSDictionary *settings in invalidSettings) {
            NSMutableDictionary *mixed = [settings mutableCopy];
            mixed[@"test.names"] = settings[@"test.names"] ?: @{@"shouldNotApply": @"test"};
            NSDictionary *before = [defaults persistentDomainForName:suite];
            assert(!YTKACEApplySettings(Document(@{@"Test": mixed}), defaults, backup, &error));
            assert([[defaults persistentDomainForName:suite] isEqual:before]);
        }
        assert(!YTKACEPreviewSettings(Document(@{@"Test": @{@"test.bool": @YES}}, @2), NULL, &error));
        assert(!YTKACEPreviewSettings(Document(@{@"Test": @{@"test.bool": @YES}}, @YES), NULL, &error));
        assert(!YTKACEPreviewSettings(Document(@{@"Test": @[]}), NULL, &error));
        assert(!YTKACEPreviewSettings([@"[]" dataUsingEncoding:NSUTF8StringEncoding], NULL, &error));
        assert(!YTKACEPreviewSettings([NSMutableData dataWithLength:1024 * 1024 + 1], NULL, &error));
        // A backup write failure must not partially import.
        NSDictionary *before = [defaults persistentDomainForName:suite];
        assert(!YTKACEApplySettings(valid, defaults, [directory URLByAppendingPathComponent:@"missing/file"], &error));
        assert([[defaults persistentDomainForName:suite] isEqual:before]);
        [defaults removePersistentDomainForName:suite];
        [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
        puts("Settings transfer validation, round-trip, isolation, and rollback passed.");
    }
}
