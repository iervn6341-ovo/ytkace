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

November 20 screenshot/layout and work regressions:

- `--composite-quality-regression --content-sheet-chrome` wraps a 252pt native
  dialog inside a 700pt controller root, with a grabber and background outside
  the dialog. The adapter must borrow only the dialog, keep the native controller
  in its original parent, size the menu below 400pt, and fit its multiline footer
  at the actual content width. Combine with `--content-next-step` to verify
  container reuse and exact-once selection after this narrower borrowing boundary.
  Add `--content-dialog-discovery` to omit the `actionSheetView` getter and
  exercise named inner-dialog discovery instead.
- `--decode-work-regression` creates a ready ELM row followed by short rows,
  including one that grows after 80 ms. The ready handler must be decoded once,
  while the late row and original leaf callbacks remain available. The previous
  revision (`598f552`) fails the same fixture with seven handler reads; it also
  fails the sheet-chrome fixture by borrowing the whole controller root.
- `gear layout-ready` now reports `elapsedMs` and `decodeMs`; the content route
  includes selected bounds and original sheet bounds. No visible native text is
  logged. The latest revision marker is `rowRenderer=fitted-content-v5`.

Additional recheck cases:

- Add `--content-outer-wrapper` to the chrome fixture to make `actionSheetView`
  return the outer 700pt controller root. A recognized inner dialog must still
  take precedence. `--content-outside-spacer` places the unnamed, handler-less
  one-point spacer outside the actual dialog; it must not prevent full native
  content from appearing in the shared shell. Combine the outer-wrapper case
  with `--content-unknown-inner` to remove the known inner class: the oversized
  getter root must then retain the original native presentation, never bypass
  the tight-root check. The ordinary plain-root selector still adapts normally.
- `--content-reflow` starts with a 520pt surface and a constrained multiline
  paragraph. At the actual narrower cell width, the paragraph must receive its
  full fitted height and the row must grow, with the original geometry restored
  on close. The test also fits successive narrow/wide widths and returns to the
  displayed width. Add `--content-reflow-constraints` to pin the original surface
  with external width/height/position constraints and verify their restoration.
  `--content-reflow-manual` exercises an older frame-based dialog that supplies
  `sizeThatFits` and lays out its paragraph manually; it must also grow for the
  narrower width. Without honoring that method, the label receives its height
  but overflows the unchanged surface and is clipped by the cell.
- These three new conditions fail revision `aeb2fc8`: the outer wrapper is still
  borrowed, the external spacer causes a native fallback, and the paragraph gets
  about 64pt instead of the required 108pt. The corrected fitting case allocates
  108pt and grows the surface from about 260pt to 304pt. These are fixture
  measurements, not device YouTube frame-rate or latency measurements.

November 20 navigation lifecycle audit (launch each case separately):

| Launch flag | Required behavior |
| --- | --- |
| `--flow-model-sync`, `--flow-model-async` | Original model callback runs after native close, once; detached-source child requests retain the saved presenter, shared container and Back history. |
| `--flow-layout-generation` | Re-entering during presentation and pending layout preserves original alpha; retired retries cannot reveal the new sheet; cancellation closes once. |
| `--flow-session-generation` | An old owner's delayed completion cannot unhide a freshly reopened session on the same controller. |
| `--flow-mask-generation` | Cancelling an interactive session and reopening as metadata clears only its owned mask; the late completion cannot mutate the replacement. |
| `--flow-retained-async` | A non-dismissing native command can request its child asynchronously with shared container and Back history. |
| `--flow-background`, `--flow-retained-background` | Deactivation cancels pending origin/history and transition cover; original native teardown still completes once; late child requests do not revive adaptation. |
| `--flow-windows` | Two independent windows request delayed ELM children from detached sources; each keeps its own presenter, anchor and completion. |

With the same fixtures, revision `c0651a4` loses both model-handler children,
allows old owner completions to change a replacement session, revives floating
menus after deactivation, and mixes interleaved ELM windows. The retained-owner
async case also serves as a preservation check. These are UIKit fixture results;
they do not establish real-device YouTube transition latency or binary compatibility.
The layout re-entry case passes the baseline too, so it is a preservation check,
not evidence of a reproduced baseline failure. In a separate mutated build,
inverting the session restoration generation check makes
`--flow-session-generation` fail as expected; the unchanged implementation passes.
During the broader matrix, native activation exceeded the unchanged 100 ms
startup assertion once. Three isolated reruns passed; the failure diagnostic now
includes mode and elapsed milliseconds. This does not certify a device latency
bound or explain the unrepeatable timing outlier.
The final audit also rendered the 850 ms child and the manual multiline content
fixture: Back/close remained visible, the native grabber/outer root stayed out
of the shared menu, and the full paragraph fit within its resized content page.

Visual QA: the interactive speed fixture was rendered and inspected on the
  disposable iPhone 17 simulator (iOS 27.2). The shared header, close button,
  native slider, choice and gear anchor were visible. The physics regression
  preview also retained the full 192pt content with a 44pt outer sheet item.
  This is a stand-in selector,
  not a screenshot or timing certification of YouTube's private UI.
  On November 20 the sheet-chrome fixture was also rendered and inspected on
  that simulator: the outer root/grabber was absent, the menu ended immediately
  after the 252pt dialog content, and the Chinese footer wrapped within the panel.
  The recheck preview combined an outer getter wrapper, external spacer and fixed
  source-size constraints with the longer paragraph, using both Auto Layout and
  native `sizeThatFits` sizing. All text remained visible after the surface grew
  to about 304pt, with no borrowed grabber or outer root.
- Controls `--direct-quality-regression` additionally removes the controls view's
  playerViewController, resolves the player through eventsDelegate.delegate, and
  applies a real format constraint to its playerItem. Existing direct format,
  Auto, deduplication, stale-video and unavailable-API cases remain covered.

These fixtures exercise the production adapter with stand-in YouTube objects;
actual YouTube 21.11.4 device presentation and private API availability still need
verification with the packaged build.
