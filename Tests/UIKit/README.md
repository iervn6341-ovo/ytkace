# Player menu UIKit smoke app

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
