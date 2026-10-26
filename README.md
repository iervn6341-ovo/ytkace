# YTKACE

An open-source YouTube enhancement for iOS.

## Features

| Area | Included |
|---|---|
| Downloads | Video, audio, Shorts and whole-playlist downloads; save to the library, Photos or the share sheet; sorting; backup and restore |
| Queue | Play next or play last without Premium, with reorder, swipe to remove, shuffle, loop and clear |
| Playback | Background playback, PiP, loop, speed controls, default speed, gestures, tap to seek and an HLS playback mode |
| SponsorBlock | Category controls, progress markers, skip modes and configurable alerts |
| Interface | OLED mode, overlay controls, navigation cleanup and native share sheets |
| Liquid Glass | Glass tab bar, top bar buttons, menus, sheets, player buttons and YTKACE popups on iOS 26, with shrink on scroll and a selected tab color |
| Tabs | Hide, reorder and add YouTube destinations |
| Library | Downloaded video, Shorts and audio players with resume support |
| Settings | Searchable settings, 15 languages and a native YouTube settings section |

## Compatibility

- **iOS:** 15.0 and newer (tweak packages); the prebuilt IPAs follow their YouTube base
- **Architecture:** arm64
- **YTKACE:** 1.1.3

YouTube 21.41.5 requires iOS 17, so two IPAs are published:

| IPA | YouTube base | iOS |
| --- | --- | --- |
| `YTKACE_1.1.3_YouTube_iOS16_21.33.6.ipa` | 21.33.6 | 16.0 and newer |
| `YTKACE_1.1.3_YouTube_21.41.5.ipa` | 21.41.5 | 17.0 and newer |

Pick the 21.41.5 build unless you are on iOS 16. Either one installs with TrollStore or a developer-certificate sideloader.

## Install

**Jailbroken.** Add the repository in Sileo, Zebra or Cydia:

```
https://itzzace.github.io/ytkace/
```

Rootless and roothide packages are both published. The repository page also has an
[Add to Sileo](https://itzzace.github.io/ytkace/) button.

**Sideloaded.** Download the IPA for your iOS version from the [latest release](https://github.com/itzzace/ytkace/releases/latest) and install it with TrollStore, AltStore, SideStore or LiveContainer.

## Build

Fork the repository, enable Actions, open the **IPA** workflow and provide a direct link to a decrypted YouTube IPA you are legally allowed to use. The completed workflow provides the injected IPA as an artifact. The **Deb** workflow builds the tweak package.

To build both IPAs in one run, fill in the second URL field as well: the workflow takes an iOS 16 base (21.33.6) and an optional iOS 17+ base (21.41.5), and uploads them as separate artifacts. Leaving the second field empty builds a single IPA.

## Settings

Open the YTKACE tab and tap the gear, or open YouTube Settings and choose YTKACE.
Both pages carry the same options, and the YouTube Settings section has a search bar.

When the integrated CaptionIsland factory is loaded, **Caption Island** appears in this
menu and search. The bridge resolves the factory on use, so standalone YTKACE has no
hard dependency on CaptionIsland. **General → Use System Menus** selects UIKit list
sheets/popovers for tweak-owned choices, download menus, library actions, transcripts
and sleep timers. Menus use an explicit `UIGlassEffect` background when supported,
respect Reduce Transparency, and retain their original action callbacks. This does
not replace every server-driven YouTube menu; native host menus need separate adapters.

### Player controls

YTKACE owns its player buttons, including the integrated YouQuality-style shortcut.
Enable **Quality Button** under **Video Quality**. The text opens YouTube's native
quality selector; its selected-format callback updates the compact label (4K, 2K,
1080p, etc.) and full accessibility value. A new video shows Auto until a selection
is reported. Existing YouQuality visibility preferences migrate once. The code
retains PoomSmart's MIT notice in `YTKACE.bundle/Licenses/YouQuality.txt`.

Buttons fill the native top band, then a second trailing row below the gear, using
44pt targets, 24pt icons and 6pt spacing. **Player → Player Button Layout** defaults to Expanded: crowded rows scroll
horizontally without a More button. More Menu restores the compact layout. Downloads
get the first visible slot when their overlay placement is enabled. Native reservations are cached while controls fade/auto-hide, so
opacity changes do not move custom buttons into the cast/CC/gear slots. Rotation
invalidates the cache. YTKACE does not register with or load YTVideoOverlay;
CaptionIsland independently retains its existing bottom-button integration.

Local layout yields to active pans, controller transitions and invalid geometry,
then resumes after completion/cancellation. Player-glass styling reuses native
Liquid Glass and preserves native layers during transforms. System menus measure
actual table content for their popover/sheet height instead of a fixed estimate.
Console diagnostics use `[YTKACE PlayerControls]` and `[YTKACE PlayerGlass]`.

### Telemetry Audit

The audit page includes an observed-request list with host/method/service/path search
and a selectable, copyable detail page. Recording and request-detail capture both
default to off. Optional details sanitize URL/query/header fields and bounded JSON
bodies before writing; raw credentials, input streams, compressed and binary bodies
are not stored. Only selected client fields and boolean flags retain values. Existing
metadata-only entries remain readable but cannot recover omitted content. The browser
refreshes from a background snapshot while visible at the top, with manual refresh
available when scrolled. Logs rotate at 768 KB. This remains a passive NSURLSession
resume observer, not a full response/network capture.

### Player menus beside buttons

With General → Use System Menus enabled, YTKACE player menus use UIKit popovers
on iPhone and iPad, anchored to the visible player button. The popover delegate
prevents compact-width adaptation into a bottom sheet. UIKit supplies the native
material, including Liquid Glass on supported systems, without an extra glass
layer over the player menu. Selected/disabled actions, subtitles and callbacks
retain their behavior; settings outside the player keep their existing sheets.

The presenter recognizes YouTube's default/action/contextual player sheet containers.
For complete action models it rebuilds their choices as a self-sizing UIKit popover,
including icons, values, selection and disabled state. The original sheet's modal
style and transitioning delegate are preserved: it completes its native lifecycle
behind the replacement list and closes before the original action runs. Closing or
tapping outside the list also closes that native session, so quality/submenu state
can be released. Native content is never cropped into an estimated popover rectangle.

Custom controls, incomplete/unknown action models and unavailable anchors retain
the original sheet, styled by Liquid Glass → Menus and Sheets where supported.
This is a bounded adapter, not a universal replacement for YouTube's server-driven
screens. Console tags `[YTKACE PlayerMenus]` and `[YTKACE Quality]` report adaptation,
fallback and action routing without video/account details. Actual YouTube versions
still require device validation. Bounds adapt to the safe area and the native
popover repositions on rotation; long option lists remain scrollable.

### Settings transfer for integrated tweaks

General contains Copy/Paste Settings and JSON file import/export. Imports preview the
number of supported/changed/unknown entries, validate all known values before writing,
and save `Documents/YTKACE/Settings-before-import.json`. Restore Previous Settings
restores that snapshot; restart YouTube after importing. This versioned format is
settings-only and does not accept uYouEnhanced's legacy `key: value` text.

`Tweak/Runtime/SettingsTransfer.h` exposes an opt-in registration function. A separately
loaded tweak can resolve it without adding a hard dependency on YTKACE:

```objc
#import <dlfcn.h>
// Run after dylib constructors, for example on the first main-queue turn.
typedef void (*RegisterModule)(NSString *, NSDictionary<NSString *, NSDictionary *> *);
RegisterModule registerModule = (RegisterModule)dlsym(RTLD_DEFAULT, "YTKACERegisterSettingsModule");
if (registerModule) registerModule(@"MyTweak", @{
    @"MyTweak.Enabled": @{@"default": @YES},
    @"MyTweak.Mode": @{@"default": @0, @"values": @[@0, @1]},
    @"MyTweak.Delay": @{@"default": @2.0, @"minimum": @0.0, @"maximum": @10.0}
});
```

Register only user preferences. Each key has one module owner. Rules require a default
value; optional fields are `values`, `minimum`, `maximum`, `pattern` (string regex), and
`elementType: @"number"` for numeric arrays. Booleans and numbers remain distinct.
Strings, string arrays, numeric arrays and string-to-string dictionaries are supported;
arbitrary nested objects and credentials are outside this interface. Files are limited
to 1 MB. Unknown modules/keys are skipped; malformed known values reject the entire
import. Preferences are merged without replacing YouTube's defaults domain. Registered
modules must be available before opening the transfer actions. Settings that are cached
by a tweak take effect after restarting the app.

## Screenshots

<p align="center">
  <img src="screenshots/framed/settings.png" width="220" alt="YTKACE settings">
  <img src="screenshots/framed/video-download-menu.png" width="220" alt="Video download menu">
  <img src="screenshots/framed/audio-player.png" width="220" alt="Audio player">
</p>

<p align="center">
  <sub>Settings · Downloads · Audio Player</sub>
</p>

<p align="center">
  <img src="screenshots/framed/glass-menu.png" width="220" alt="Liquid Glass menu">
  <img src="screenshots/framed/glass-quality-sheet.png" width="220" alt="Liquid Glass quality sheet">
  <img src="screenshots/framed/glass-download.png" width="220" alt="Liquid Glass download progress">
</p>

<p align="center">
  <sub>Liquid Glass · Menus · Sheets · Tab Bar</sub>
</p>

<details>
  <summary>More screenshots</summary>
  <br>
  <p align="center">
    <img src="screenshots/framed/shorts-download-menu.png" width="190" alt="Shorts download menu">
    <img src="screenshots/framed/tab-editor.png" width="190" alt="Tab editor">
    <img src="screenshots/framed/download-progress.png" width="190" alt="Download progress">
  </p>
  <p align="center">
    <img src="screenshots/framed/download-library.png" width="190" alt="Download library">
    <img src="screenshots/framed/video-player.png" width="190" alt="Downloaded video player">
    <img src="screenshots/framed/player-settings.png" width="190" alt="Player settings">
  </p>
  <p align="center">
    <img src="screenshots/framed/sponsorblock-settings.png" width="190" alt="SponsorBlock settings">
    <img src="screenshots/framed/audio-queue.png" width="190" alt="Audio queue">
  </p>
  <p align="center">
    <img src="screenshots/framed/glass-settings.png" width="190" alt="Liquid Glass settings">
    <img src="screenshots/framed/glass-share-sheet.png" width="190" alt="Liquid Glass share sheet">
    <img src="screenshots/framed/glass-home.png" width="190" alt="Liquid Glass tab bar">
  </p>
</details>

## Privacy

YTKACE has no activation service, analytics, telemetry or updater.

## Notes

The playback fix that shipped after 0.8.0 was taken from another project without credit and has been removed. The current Playback Fix is adapted from Mark02's YTPlaybackFix under the MIT license and is credited in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). If you find anything else that isn't credited, open an issue and it will be credited or removed.

## Contributing

Contributions are welcome — issues and pull requests both help.

For bug reports, include your device, iOS version and YouTube version.

For pull requests, keep each one focused on a single change and match the
surrounding style. Two things worth knowing:

- Hooks are installed by name through the helpers in `Tweak/Runtime/Hooking.h`,
  not a hooking framework, so a missing class or selector fails quietly instead
  of crashing on older YouTube versions.
- New user-facing strings go through `YTKACELocalized` and belong in
  `Resources/YTKACE.bundle/en.lproj/Localizable.strings`. Translations for the
  other 14 languages can follow separately.

Build instructions are above.

## Donate

If YTKACE is useful to you, you can support it on [Ko-fi](https://ko-fi.com/itzzace) or with crypto:

- **BTC:** `bc1q6ahl2mghgq34r3w26yhwevsza0vl8436gugxke`
- **LTC:** `LYQ2ivZ52d2zAsm896MwWEkPEi15WwprS4`

## License

YTKACE source is available under the [MIT License](LICENSE). See [Third-Party Notices](THIRD_PARTY_NOTICES.md) for components and services with separate terms.
