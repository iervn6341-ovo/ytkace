#import "SettingsTransfer.h"
#import <CoreFoundation/CoreFoundation.h>
#include <cmath>

static const NSUInteger YTKACESettingsSizeLimit = 1024 * 1024;

static NSMutableDictionary *YTKACESettingsRegistry(void) {
    static NSMutableDictionary *registry;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ registry = [NSMutableDictionary dictionary]; });
    return registry;
}

static NSDictionary *YTKACESettingsModules(void) {
    NSMutableDictionary *registry = YTKACESettingsRegistry();
    @synchronized (registry) { return [registry copy]; }
}

NSDictionary *YTKACESettingsRule(id value) {
    return @{@"default": value};
}

void YTKACERegisterSettingsModule(NSString *identifier, NSDictionary<NSString *, NSDictionary *> *rules) {
    if (identifier.length == 0) return;
    NSMutableDictionary *registry = YTKACESettingsRegistry();
    @synchronized (registry) {
        NSMutableDictionary *merged = [registry[identifier] mutableCopy] ?: [NSMutableDictionary dictionary];
        [rules enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *rule, BOOL *stop) {
            (void)stop;
            if (key.length == 0 || rule[@"default"] == nil) return;
            // A preference has a single owner even if another module tries registering it.
            for (NSString *other in registry) {
                if (![other isEqual:identifier] && registry[other][key] != nil) return;
            }
            merged[key] = [rule copy];
        }];
        registry[identifier] = [merged copy];
    }
}

static BOOL YTKACESettingsError(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"YTKACE.SettingsTransfer" code:1
                                      userInfo:@{NSLocalizedDescriptionKey: message}];
    return NO;
}

static BOOL YTKACEBoolean(id value) {
    return [value isKindOfClass:NSNumber.class] &&
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

static BOOL YTKACEValidSetting(id value, NSDictionary *rule) {
    id fallback = rule[@"default"];
    BOOL valid = NO;
    if (YTKACEBoolean(fallback)) valid = YTKACEBoolean(value);
    else if ([fallback isKindOfClass:NSNumber.class]) {
        valid = [value isKindOfClass:NSNumber.class] && !YTKACEBoolean(value) && std::isfinite([value doubleValue]);
        if (valid && rule[@"minimum"]) valid = [value doubleValue] >= [rule[@"minimum"] doubleValue];
        if (valid && rule[@"maximum"]) valid = [value doubleValue] <= [rule[@"maximum"] doubleValue];
    } else if ([fallback isKindOfClass:NSString.class]) {
        valid = [value isKindOfClass:NSString.class] && [value length] <= 4096;
        if (valid && rule[@"pattern"]) {
            NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:rule[@"pattern"] options:0 error:nil];
            valid = expression && [expression numberOfMatchesInString:value options:0 range:NSMakeRange(0, [value length])] == 1;
        }
    } else if ([fallback isKindOfClass:NSArray.class]) {
        valid = [value isKindOfClass:NSArray.class] && [value count] <= 256;
        if (valid) for (id item in value) {
            // Settings lists currently contain strings. Other tweaks may register numeric lists.
            id element = [rule[@"elementType"] isEqual:@"number"] ? @0 : @"";
            if (!YTKACEValidSetting(item, YTKACESettingsRule(element))) { valid = NO; break; }
        }
    } else if ([fallback isKindOfClass:NSDictionary.class]) {
        valid = [value isKindOfClass:NSDictionary.class] && [value count] <= 256;
        if (valid) for (id key in value) {
            if (![key isKindOfClass:NSString.class] || [key length] > 128 ||
                !YTKACEValidSetting(value[key], YTKACESettingsRule(@""))) { valid = NO; break; }
        }
    }
    if (valid && rule[@"values"]) valid = [rule[@"values"] containsObject:value];
    return valid;
}

NSData *YTKACEExportSettings(NSUserDefaults *defaults, NSError **error) {
    NSMutableDictionary *modules = [NSMutableDictionary dictionary];
    NSDictionary *registry = YTKACESettingsModules();
    for (NSString *module in registry) {
        NSMutableDictionary *settings = [NSMutableDictionary dictionary];
        for (NSString *key in registry[module]) {
            NSDictionary *rule = registry[module][key];
            id value = [defaults objectForKey:key] ?: rule[@"default"];
            settings[key] = YTKACEValidSetting(value, rule) ? value : rule[@"default"];
        }
        modules[module] = settings;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{
        @"format": @"YTKACE.Settings", @"version": @1, @"modules": modules
    } options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:error];
    if (data.length > YTKACESettingsSizeLimit) {
        YTKACESettingsError(error, @"Settings exceed the 1 MB limit.");
        return nil;
    }
    return data;
}

NSDictionary *YTKACEPreviewSettings(NSData *data, NSUInteger *skipped, NSError **error) {
    if (skipped) *skipped = 0;
    if (data.length == 0 || data.length > YTKACESettingsSizeLimit) {
        YTKACESettingsError(error, @"Settings must be a JSON file smaller than 1 MB."); return nil;
    }
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!root) return nil;
    if (![root isKindOfClass:NSDictionary.class] || ![root[@"format"] isEqual:@"YTKACE.Settings"] ||
        ![root[@"version"] isKindOfClass:NSNumber.class] || YTKACEBoolean(root[@"version"]) ||
        ![root[@"version"] isEqual:@1] || ![root[@"modules"] isKindOfClass:NSDictionary.class]) {
        YTKACESettingsError(error, @"Unsupported settings format or version."); return nil;
    }
    NSDictionary *registry = YTKACESettingsModules();
    NSMutableDictionary *changes = [NSMutableDictionary dictionary];
    for (NSString *module in root[@"modules"]) {
        id settings = root[@"modules"][module];
        if (![settings isKindOfClass:NSDictionary.class]) {
            YTKACESettingsError(error, @"A settings module is malformed."); return nil;
        }
        for (NSString *key in settings) {
            NSDictionary *rule = registry[module][key];
            if (!rule) { if (skipped) ++*skipped; continue; }
            if (!YTKACEValidSetting(settings[key], rule)) {
                YTKACESettingsError(error, [NSString stringWithFormat:@"Invalid setting: %@", key]); return nil;
            }
            changes[key] = settings[key];
        }
    }
    if (changes.count == 0) { YTKACESettingsError(error, @"No supported settings were found."); return nil; }
    return [changes copy];
}

BOOL YTKACEApplySettings(NSData *data, NSUserDefaults *defaults, NSURL *backupURL, NSError **error) {
    NSDictionary *changes = YTKACEPreviewSettings(data, NULL, error);
    if (!changes) return NO;
    NSData *backup = YTKACEExportSettings(defaults, error);
    if (!backup || ![backup writeToURL:backupURL options:NSDataWritingAtomic error:error]) return NO;
    // Validate the entire document and save a recoverable snapshot before writing any preference.
    for (NSString *key in changes) [defaults setObject:changes[key] forKey:key];
    return YES;
}
