# Player menu UIKit smoke app

For the independent player controls/transition/PlayerGlass regression, build
`bash Tests/UIKit/build_player_controls_smoke.sh /tmp/PlayerControlsSmoke.app`.
Launch `dev.captionisland.player-controls-smoke` on a disposable iPhone simulator
and read `Documents/result.txt`. It uses the production host and glass hooks with
fake native classes, including glass on/keep-controls off, repeated transforms,
compact/expanded two-row packing, horizontally scrollable crowded rows, download/PiP
grouping at the start of the second row in portrait and wide players, native
fade/auto-hide geometry reservations and integrated quality
labels, model/controller identity differences, immediate selection/constraint updates,
Auto reset, old-video callback isolation and repeated native action routing,
cancelled pans, zero size, native glass reuse and layout reentry. It does not load
YTVideoOverlay or simulate YouTube's private transition controller.

From the YTKACE root, build with a selected Xcode:

```sh
bash Tests/UIKit/build_player_menu_smoke.sh /tmp/PlayerMenuSmoke.app
```

Install/launch on a test iPhone simulator:

```sh
xcrun simctl install booted /tmp/PlayerMenuSmoke.app
xcrun simctl launch booted dev.captionisland.player-menu-smoke
xcrun simctl get_app_container booted dev.captionisland.player-menu-smoke data
```

Read `Documents/result.txt` in the returned container after the scheduled checks
complete. The app exercises the production presentation code and hook utility:
compact-width popover adaptation, visible button anchoring, window containment,
selection and disabled actions, long-list scrolling, landscape rotation,
dismissal-before-callback, native-container
routing with preserved native lifecycle and glass, unrelated/settings controller scope, and the feature preference.
Ownership tests use an unregistered native gear with a spoofed tweak identifier,
a registered tweak gear icon and a registered quality button. Unregistered native
controls keep original presentation without reading action titles. Fresh tweak-source tokens are cleared by native control activation
and by the production touch-origin observer (called with a view fixture, not HID).
The known native gear has separate tests requiring an actual popover, native live
rows without title extraction, a window-space anchor while the gear is hidden,
anchored submenus, cancellation/reopening and original owner lifecycle. The gear
fixture reproduces the device's index-3 ELM control with 398 x -0 bounds and a
separate row that gains height 80 ms after appearance: the final popover must omit
only the collapsed row and include the late row, with four native rows in total.
A CaptionIsland-shaped factory action is appended at native index 6 with a title,
icon and subsequently assigned zero-argument handler but no button. The popover
must have five mixed rows, display that extension's title/icon, close the native
owner, and execute the extension exactly once before its submenu opens.
Launch with
`--preview-native-gear` and wait for `Documents/gear-preview.txt` to hold that state
for screenshots. This preview mode does not produce a new full-suite PASS.
Quality coverage includes absent callbacks, unreadable non-Auto callbacks, explicit
menu choice persistence, temporary missing metadata and confirmed native-control
activation, as well as a differently wrapped callback model.
The 1080p check measures the actual button title rectangle and its minimum font
width. `--preview-quality-label` finishes the controls suite and then holds the
selected label in view after `Documents/quality-preview.txt` is written.
The controls build first checks QualityControls.mm with deprecated declarations
enabled as errors, before compiling the wider fixture with its older UIKit APIs.
ELM fixtures include yoga children and controller/materialized node chains without
UIView/subnodes/accessibility text. Native fallback cancellation verifies transformed
panel inside/outside acceptance using a UITouch location fixture and normal recognizer
target/action delivery, including original owner and transition callbacks. It does
not inject physical touch events.
An opaque row fixture draws its content without any readable text property. The
actual control is borrowed into the list and restored with its original constraints
on cancellation/selection, while the original action executes once.
For a held visual preview, launch with `--preview-native-row` and wait for
`Documents/preview-ready.txt`. This mode holds the opaque row popover for screenshots;
it does not complete the regression or write a new PASS result.
It leaves an example player popover visible after passing.

The YouTube view/controller names are stand-ins. This verifies UIKit routing,
not private YouTube layouts. Device QA should cover portrait/full-screen
landscape, rotation while open, long options with large Dynamic Type, overflow
buttons, submenus, tap-outside dismissal and Reduce Transparency. Test YouTube's
gear, YouQuality and speed menus on the actual version being packaged. Unsupported
container classes retain the app's original presentation.

Actions compiles this harness but does not boot a simulator or claim runtime UI
coverage from compilation alone. The harness and its fake classes are not linked
into the shipped tweak.
