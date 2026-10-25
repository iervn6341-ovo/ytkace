#import "TelemetryRecord.h"
#import <CoreFoundation/CoreFoundation.h>

static NSString *const Mask = @"[redacted]";
static BOOL Matches(NSString *text, NSString *pattern) {
    return text.length <= 256 && [text rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
}
static BOOL Domain(NSString *host, NSString *suffix) {
    return [host isEqual:suffix] || [host hasSuffix:[@"." stringByAppendingString:suffix]];
}
static NSString *Service(NSString *host) {
    for (NSString *suffix in @[@"youtube.com", @"googleapis.com", @"googlevideo.com", @"google.com", @"gstatic.com", @"ggpht.com"])
        if (Domain(host, suffix)) return @"Google / YouTube";
    if ([host isEqual:@"sponsor.ajay.app"]) return @"SponsorBlock";
    if ([host isEqual:@"dearrow-thumb.ajay.app"]) return @"DeArrow";
    if ([host isEqual:@"lrclib.net"]) return @"LRCLIB";
    return @"Other";
}
static NSString *FieldName(NSString *name) {
    return Matches(name, @"^[A-Za-z_][A-Za-z0-9_.-]{0,47}$") ? name : @"[field]";
}
static BOOL Sensitive(NSString *key) {
    NSString *lower = key.lowercaseString;
    for (NSString *token in @[@"auth", @"cookie", @"token", @"secret", @"password", @"visitor", @"tracking", @"signature", @"session", @"email", @"account", @"userid", @"user_id", @"gaia", @"deviceid", @"device_id", @"credential", @"apikey", @"api_key", @"searchquery"])
        if ([lower containsString:token]) return YES;
    return NO;
}
static id SafeValue(id value, NSString *key, NSUInteger depth, NSUInteger *remaining) {
    if (*remaining == 0 || depth > 7) return @"[limit]";
    --*remaining;
    if (Sensitive(key)) return Mask;
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        NSUInteger unnamed = 0;
        for (NSString *field in [[value allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            if (*remaining == 0) { out[@"[more fields]"] = @"[limit]"; break; }
            NSString *name = FieldName(field);
            if ([name isEqual:@"[field]"]) name = [NSString stringWithFormat:@"[field %lu]", (unsigned long)++unnamed];
            out[name] = SafeValue(value[field], field, depth + 1, remaining);
        }
        return out;
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *out = [NSMutableArray array];
        for (id item in value) {
            if (out.count >= 12 || *remaining == 0) { [out addObject:@"[limit]"]; break; }
            [out addObject:SafeValue(item, key, depth + 1, remaining)];
        }
        return out;
    }
    if (value == NSNull.null) return value;
    if ([value isKindOfClass:NSNumber.class]) {
        if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return value;
        if ([@[@"screenWidthPoints", @"screenHeightPoints", @"screenPixelDensity", @"widthPixels", @"heightPixels", @"clientName", @"errorCode"] containsObject:key] &&
            [value doubleValue] >= 0 && [value doubleValue] <= 100000) return value;
    }
    if ([value isKindOfClass:NSString.class]) {
        if ([@[@"clientVersion", @"osVersion"] containsObject:key] && Matches(value, @"^[0-9]+(?:[._-][0-9]+){0,5}$")) return value;
        if ([key isEqual:@"hl"] && Matches(value, @"^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8}){0,2}$")) return value;
        if ([key isEqual:@"gl"] && Matches(value, @"^[A-Za-z]{2}$")) return value;
        if ([key isEqual:@"clientName"] && [@[@"IOS", @"ANDROID", @"WEB", @"MWEB", @"TVHTML5", @"VISIONOS"] containsObject:value]) return value;
        if ([key isEqual:@"osName"] && [@[@"iOS", @"Android", @"Macintosh", @"Windows", @"Linux", @"visionOS"] containsObject:value]) return value;
    }
    return Mask;
}

NSDictionary *YTKACETelemetrySnapshot(NSURLRequest *request, BOOL details) {
    NSURL *url = request.URL;
    NSString *host = url.host.lowercaseString ?: @"";
    NSData *body = request.HTTPBody;
    BOOL stream = request.HTTPBodyStream != nil;
    NSMutableDictionary *record = [@{@"id": NSUUID.UUID.UUIDString, @"observedAt": NSDate.date,
        @"host": host, @"service": Service(host), @"method": request.HTTPMethod.uppercaseString ?: @"GET",
        @"bodyBytes": @(body.length), @"bodySizeKnown": @(body != nil),
        @"bodySource": stream ? @"stream (size unknown)" : (body ? @"data" : @"not exposed / empty"),
        @"detailsCaptured": @(details)} mutableCopy];
    NSMutableOrderedSet *classes = [NSMutableOrderedSet orderedSet];
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    NSDictionary *rawHeaders = request.allHTTPHeaderFields ?: @{};
    for (NSString *name in [[rawHeaders allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *key = name.lowercaseString;
        NSString *category = Sensitive(key) ? @"authentication / identifiers" :
            ([key containsString:@"language"] || [key containsString:@"locale"] ? @"locale" :
            ([key containsString:@"client"] || [key containsString:@"version"] || [key isEqual:@"user-agent"] ? @"client metadata" : @"other headers"));
        if ([key isEqual:@"cookie"] || [key isEqual:@"set-cookie"]) category = @"cookies";
        [classes addObject:category];
        if (!details || headers.count >= 64) continue;
        NSString *value = rawHeaders[name];
        NSString *safe = Mask;
        if ([key isEqual:@"content-type"]) {
            NSString *mime = [[value componentsSeparatedByString:@";"] firstObject].lowercaseString;
            if (Matches(mime, @"^[a-z0-9.+-]+/[a-z0-9.+-]+$")) safe = mime;
        } else if ([key isEqual:@"content-length"] && Matches(value, @"^[0-9]{1,12}$")) safe = value;
        else if ([key isEqual:@"x-youtube-client-version"] && Matches(value, @"^[0-9]+(?:[.][0-9]+){1,5}$")) safe = value;
        else if ([key isEqual:@"x-youtube-client-name"] && Matches(value, @"^[0-9]{1,3}$")) safe = value;
        headers[FieldName(name)] = safe;
    }
    record[@"headerClasses"] = classes.array;
    if (!details) return record;
    record[@"scheme"] = [@[@"https", @"http"] containsObject:url.scheme.lowercaseString] ? url.scheme.lowercaseString : @"other";
    record[@"headers"] = headers;
    NSMutableArray *path = [NSMutableArray array];
    NSSet *segments = [NSSet setWithArray:@[@"youtubei", @"v1", @"player", @"next", @"browse", @"search", @"log_event", @"get_transcript", @"videoplayback", @"api", @"skipSegments", @"branding", @"get", @"search"]];
    for (NSString *part in url.path.pathComponents) {
        if ([part isEqual:@"/"] || !part.length) continue;
        if (path.count >= 12) { [path addObject:@"[limit]"]; break; }
        [path addObject:[segments containsObject:part] ? part : @"[segment]"];
    }
    record[@"pathPreview"] = [@"/" stringByAppendingString:[path componentsJoinedByString:@"/"]];
    NSMutableArray *query = [NSMutableArray array];
    if (url.absoluteString.length <= 16384) {
        for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) {
            if (query.count >= 32) { [query addObject:@{@"name": @"[limit]", @"value": Mask}]; break; }
            [query addObject:@{@"name": FieldName(item.name), @"value": Mask}];
        }
    }
    record[@"queryParameters"] = query;
    if (stream) record[@"bodyPreviewStatus"] = @"Stream not read; size is unknown.";
    else if (!body.length) record[@"bodyPreviewStatus"] = @"No in-memory body exposed; may be empty or supplied by another API.";
    else if (body.length > 32 * 1024) record[@"bodyPreviewStatus"] = @"Body exceeds the 32 KB inspection limit; not read.";
    else {
        NSString *mime = [[[request valueForHTTPHeaderField:@"Content-Type"] componentsSeparatedByString:@";"] firstObject].lowercaseString;
        NSString *encoding = [request valueForHTTPHeaderField:@"Content-Encoding"].lowercaseString;
        if (encoding.length && ![encoding isEqual:@"identity"])
            record[@"bodyPreviewStatus"] = @"Compressed body; bytes not decoded or recorded.";
        else if (mime.length && ![mime isEqual:@"application/json"] && ![mime isEqual:@"text/json"] && ![mime hasSuffix:@"+json"])
            record[@"bodyPreviewStatus"] = @"Non-JSON content type; bytes not decoded or recorded.";
        else record[@"pendingBody"] = [body copy];
    }
    return record;
}

NSDictionary *YTKACETelemetryFinalize(NSDictionary *snapshot) {
    NSMutableDictionary *record = [snapshot mutableCopy];
    NSDate *date = record[@"observedAt"];
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [NSISO8601DateFormatter new];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    });
    @synchronized (formatter) { record[@"timestamp"] = [formatter stringFromDate:date]; }
    [record removeObjectForKey:@"observedAt"];
    NSData *body = record[@"pendingBody"];
    [record removeObjectForKey:@"pendingBody"];
    if (body) {
        id json = [NSJSONSerialization JSONObjectWithData:body options:NSJSONReadingFragmentsAllowed error:nil];
        if (json) {
            NSUInteger remaining = 120;
            id safe = SafeValue(json, @"", 0, &remaining);
            NSData *preview = [NSJSONSerialization dataWithJSONObject:safe options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys | NSJSONWritingFragmentsAllowed error:nil];
            if (preview.length && preview.length <= 8192) {
                record[@"bodyPreview"] = [[NSString alloc] initWithData:preview encoding:NSUTF8StringEncoding];
                record[@"bodyPreviewStatus"] = @"JSON structure with selected client fields; other values redacted.";
            } else record[@"bodyPreviewStatus"] = @"Sanitized preview exceeds 8 KB; omitted.";
        } else record[@"bodyPreviewStatus"] = @"Non-JSON, compressed, or binary body; bytes not recorded.";
    }
    return record;
}
