# Player menu UIKit smoke app

For the independent player controls/transition/PlayerGlass regression, build
`bash Tests/UIKit/build_player_controls_smoke.sh /tmp/PlayerControlsSmoke.app`.
Launch `dev.captionisland.player-controls-smoke` on a disposable iPhone simulator
and read `Documents/result.txt`. It uses the production host and glass hooks with
fake native classes, including glass on/keep-controls off, repeated transforms,
two-row packing, native fade/auto-hide geometry reservations and integrated quality
labels, per-video state and native action routing,
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
routing, unrelated/settings controller scope, and the feature preference.
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
