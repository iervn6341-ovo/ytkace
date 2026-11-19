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

`--glass-work-regression` also measures 100 steady-state layouts per glass state.
It warms each state once to separate one-time material restoration from repeated
work. Instrumented native classes count actual native layout callbacks, receiver
`superview` reads and a descendant probe's `subviews` reads. Results are written
to `Documents/result.txt.work`; all native callback counts must remain 100.
The fixture also checks disabled-layout reentry, native alpha updates while the
feature is off, reparenting out of/back into the player, and state recovery.

Measured on the disposable iOS 27.2 simulator, before/after this optimization:

| State | Receiver parent reads | Descendant probe reads |
| --- | ---: | ---: |
| Stable control | 600 → 600 | 100 → 100 |
| Feature disabled | 200 → 0 | 0 → 0 |
| Transformed control | 600 → 500 | 100 → 0 |
| Interactive pan | 600 → 500 | 100 → 0 |
| Invalid bounds | 200 → 100 | 100 → 0 |
| Large native surface | 200 → 100 | 100 → 0 |
| Offscreen player hierarchy | 400 → 0 | 100 → 0 |

These counts demonstrate eliminated hierarchy work, not measured CPU, frame-time
or energy improvements on a device. Stable-state scanning intentionally remains
so an asynchronously inserted native glass effect is detected. For baseline
comparison, add `--measure-glass-work` to retain measurements and lifecycle checks
while skipping the new scan-count and disabled-reentry assertions.

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

November 19 regressions:

- `--rebuild-back-regression` makes each gear activation create fresh owners,
  controllers and ELM nodes, and clears every dismissed owner's actions. It checks
  two submenu levels, Back route replay, repeated Back taps, fresh root entry and
  exact-once leaf selection. Add `--changed-back-regression` to change the root
  action count during reconstruction: replay must stop at the fresh floating root.
- `--elm-command-regression --back-regression --retained-back-regression` checks
  Back when the original command intentionally keeps its parent presented.
- `--elm-command-regression --back-regression` checks the leading Back button,
  reopening the parent through the gear entry, reentering its child, and exact-once
  selection after returning. The ordinary ELM suite also requires a Back item on
  each adapted child and keeps the source visually masked during command dispatch.
- Add `--late-back-regression` to the ELM/Back launch to request the child
  350 ms after selection, after its native source has gone away. Back must still
  appear, return to the parent, and allow reentry. For a held visual preview,
  use `--elm-command-regression --late-back-regression --preview-late-child`;
  wait for `Documents/late-child-preview.txt`. The ordinary ELM suite also
  releases the source's owner before that late request, rejects duplicate row
  selection, checks command dispatch within 100 ms of selection, and verifies
  that a fresh player touch prevents stale Back history on a subsequent menu.
- `--composite-quality-regression` embeds a complete native selector in the same
  floating component, with a live slider and original choice handler. It checks
  one owner dismissal and one native dismissal override, restored geometry/masks,
  exact-once selection and retained slider gestures. A real `UIDynamicAnimator`
  continues to own the outer `YTDraggableView` inside `YTSheetContainerView`;
  only the inner content controller joins the floating page, with its UIKit
  parent restored before native callbacks. Variants: `--native-content-speed`, `--content-cancel`,
  `--content-no-model`, `--content-switch-form`, `--content-background`, `--content-text-input`, `--content-next-step` and
  `--content-tweak-source`. The next-step case requires reuse of the exact same
  presentation instance. `--content-self-presenter` exercises requests made by
  the borrowed controller itself (combine with next-step or text-input);
  `--content-self-dismiss` checks its own close request. `--content-short-shell`
  keeps a 192pt content page inside a 44pt physics item; `--content-unsafe-shell`
  removes the known inner boundary and requires an intact native fallback.
  The switch-form case also retains a metadata-only tweak
  action alongside the complete native input panel. `--preview-native-content` holds the rendered selector
  and writes `Documents/native-content-preview.txt`.
- `--device-late-child-regression` requests a submenu after 850 ms, matching the
  device trace. Its floating shell, Back history and leaf callback must survive
  the 500 ms snapshot timeout. The ordinary ELM suite includes this case too.
- `--animated-owner-regression` preserves an original animated owner close and
  its completion, without invoking that owner a second time. It does not assert
  that UIKit dismissal or the native child request is instantaneous.
- `--elm-command-regression --back-regression --other-controller-regression`
  checks a native settings controller outside the legacy sheet-class list. ELM
  children must reuse the existing container; a delayed tap on the retired list
  must not dispatch another command or disable the new page. Native UIAction and
  target/selector navigation additionally check handler start within 100 ms.

Visual QA: the interactive speed fixture was rendered and inspected on the
  disposable iPhone 17 simulator (iOS 27.2). The shared header, close button,
  native slider, choice and gear anchor were visible. The physics regression
  preview also retained the full 192pt content with a 44pt outer sheet item.
  This is a stand-in selector,
  not a screenshot or timing certification of YouTube's private UI.
- Controls `--direct-quality-regression` additionally removes the controls view's
  playerViewController, resolves the player through eventsDelegate.delegate, and
  applies a real format constraint to its playerItem. Existing direct format,
  Auto, deduplication, stale-video and unavailable-API cases remain covered.

These fixtures exercise the production adapter with stand-in YouTube objects;
actual YouTube 21.11.4 device presentation and private API availability still need
verification with the packaged build.
