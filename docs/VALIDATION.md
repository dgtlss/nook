# Validation — 2026-10-06

Environment: Apple silicon, macOS 27.2 (26B5091g), Xcode 27.0 (27A266a),
Swift 6.4. The local app was signed with the owner's Developer ID identity.
Accessibility was enabled by the owner.

## Automated checks

- `swift test`: 20 policy/persistence/recovery/placement tests passed using Swift Testing.
  The added regressions cover lost-control rejection, verification failures,
  migration from preferences without an icon field, and icon persistence.
- Swift executable and Objective-C bridge compile successfully.
- Bridge passes Clang `-Wall -Wextra -Werror -fsyntax-only` with ARC.
- App signature is verified by the packaging script.
- Final optimised `swift build -c release` app bundle built successfully.
- App icon: opaque RGB, 1024×1024, embedded sRGB; icon validator passed.
  Artwork inspected at 96, 60, 40, 29 and 16 pixels and in the native window.

## Live observations

Visibility evidence uses Accessibility, not just Nook's toggle state. Nook
scans all MenuBarAgent/Control Centre root children and stops at each app
participant. The external UI inspector exposes one menu bar surface at a
time; its menu bar screenshots did not render reliably.

| Check | Result |
| --- | --- |
| Discover installed menu bar apps | Found 12 original participants; unknown apps remain in Visible |
| Assign apps to groups using card menus | Passed; choices retained across launch |
| Hide two disposable status-item apps | Both disappeared from the discovered menu bar hierarchy |
| Show all | Both disposable apps returned |
| Hide/Peek with installed Figma | Figma disappeared, then returned on Peek |
| Always tucked isolation during Peek | Test B remained absent while Figma returned |
| Timed rehide | Figma was tucked again after the configured eight-second delay |
| Open menu through Nook | Fixture A's NSMenu delegate recorded one status-menu opening |
| Normal quit while tucked | Figma returned in MenuBarAgent's hierarchy after Quit Nook |
| Shortcut with Nook focused | Final build toggled via Control-Option-N |
| Core native controls | Battery, Clock, Wi-Fi and Control Centre remained present in observed hide and quit states |
| Failure recovery | When macOS failed to allow a fixture, Nook detected the missing participant, restored the bar and named the failure |
| Lost control recovery (0.1.1) | With ChatGPT, DBnginMenuHelper and HELO tucked, a debug-only action made Nook's status item invisible. The refresh watchdog restored all three apps, restored the control, and displayed the recovery message |
| Independent recovery (0.1.1) | Double-clicking the already-running Nook.app in Finder released the restriction and returned all three apps; no status icon or shortcut was used |
| Native control availability (0.1.1) | AppKit reported the control available while the user's three-app group was tucked |
| Icon picker (0.1.1) | All five previews were visually inspected; Dot and Leaf selection updated the selected button immediately. Leaf remained selected after restarting into the signed release. Nook was selected again after testing |
| Release packaging (0.1.1) | Optimised signed build succeeded; its application menu excludes the debug-only fault simulation |
| Installed toggle (0.1.2) | Launched from `/Applications/Nook.app`; clicking the actual MenuBarAgent-hosted Nook control tucked ChatGPT, DBnginMenuHelper and HELO. Once settled, the control remained in the host hierarchy. Clicking that same control revealed the apps |
| Repeated toggle / timer (0.1.2) | Completed three hide-to-show cycles using the retained menu bar button, including a cycle with Settings closed. Manual reveal remained open past the saved eight-second delay with rehide still enabled |
| Presets while tucked (0.1.2) | Selected Dot, Chevron, Leaf, Tiles and Nook while the three apps were hidden; the host retained Nook's button for every selection. Restored the Nook preset |

The private assessment allow-list did not reveal the disposable development
fixtures while a restriction was active, even after signing and refreshing
Launch Services registration. They returned when the restriction was released.
The underlying cause is unresolved. This result is deliberately retained as
a backend limitation rather than reported as a successful fixture Peek test.
Installed Figma did reveal correctly. A running app that cannot be allowed
may cause Nook to restore everything for safety.

Verification now checks both disappearance and return, with bounded retries
for delayed Accessibility publication. Replacing assertions releases the old
request before creating the new one, avoiding overlapping restrictions. A
generation counter rejects stale callbacks. Packaging stages and signs a new
bundle before replacing the previous build, which is retained under `build/`.

Version 0.1.1 additionally checks its native status item's visibility, window
visibility and position against current menu bar and notch-safe areas. The
three-second refresh checks it throughout an active restriction. Losing the
control releases restrictions and cancels the rehide timer. Reopening the app
always reveals everything and recreates the status item. A stable autosave
name and empty removal behavior prevent Command-drag removal of this control.
These checks measure AppKit state and geometry; they cannot prove that a
different application has not drawn over the icon. The fault simulation is
compiled only into debug builds and is absent from the release app.

## Persistent toggle correction — 0.1.2

The owner reported that 0.1.1 still hid Nook itself. This was reproduced:
the development-folder app disappeared from MenuBarAgent's participant list
under a restriction despite its own bundle ID being allowed. AppKit visibility
and geometry did not detect that condition. Launching the signed app from
`/Applications/Nook.app` retained its control. The process metadata probe
confirmed that AppKit and BaseBoard agreed on Nook's bundle ID in both locations;
the deeper reason for the system's location-sensitive behavior remains unknown.

Nook now refuses to hide from the development folder. The install script stages
and verifies the app, preserves the previous installed build, and requires Nook
to quit before replacing it. Hide verification includes Nook in the expected
host participants; the ongoing refresh restores all apps if Nook is missing
in two consecutive snapshots. It no longer treats AppKit geometry alone as
proof of a successful hide.

Left-click and Accessibility activation both toggle. A manual reveal cancels
the rehide timer and stays open until another toggle. Temporary Peek, hover
and scroll retain the configurable timer. The icon choice and three saved app
assignments were preserved.

During testing MenuBarAgent restarted (the system crash report records a
FrontBoard scene-creation trap). This left the old AppKit button reference
stale. Nook now releases restrictions on the service's termination and recreates
its status item on the service's next launch. Live testing continued against the
recovered service after restarting Nook; automatic recovery through another
system-service crash has not been deliberately induced.

## Shelf and icon hit targets — 0.1.3

- Icon tiles now declare a rectangular hit area covering their full 68×60-point
  label. Coordinate clicks in the Chevron tile's empty top-left corner and
  Leaf tile's empty right padding both changed selection. The owner's Dot
  selection was restored after testing.
- The shelf uses a nonactivating panel placed in screen coordinates rather
  than a popover attached to a remotely hosted status button. It sits six
  points below the menu bar on the icon's display and clamps horizontally to
  that display. Its height is determined by a fixed-height horizontal app row.
- Live placement on the current display: screen `{{0,0},{1710,1112}}`, menu
  bar height `37.5`, panel `{{1055.5,943.5},{470,125}}`. The panel's top is
  `1068.5`, exactly six points below the menu bar's bottom at `1074.5`.
  The shelf rendered all seven current tucked apps in one row.
- Escape dismissal was confirmed through the app's panel state (`visible=false`).
  The panel also dismisses when it resigns key status or receives an outside
  click. The automation's Finder click did not produce a dismissal log, so that
  route is not recorded as a passing live test; physical outside-click testing
  remains needed.
- Added three placement tests for menu bar adjacency, horizontal display-edge
  clamping with a negative display origin, and a notched display's taller bar.
- Optimised, Developer ID signed 0.1.3 installed in `/Applications/Nook.app`.
  The owner's current assignments, shelf preference and icon choice were retained.

## Stable shelf toggle — 0.1.4

Closing the shelf previously forced replacement of the visibility assertion even
when the allow-list was identical. Releasing the old assertion exposed every
app for the replacement delay, causing the menu bar to shift. Visibility requests
now retain the active assertion when their plan is unchanged, updating logical
reveal state separately when needed. Genuine changes, including clearing a
temporary app reveal, still update the visibility plan.

The signed release was installed in `/Applications/Nook.app`. Twenty core tests
passed. Three live open/close cycles through MenuBarAgent's Nook button showed
and dismissed the shelf while retaining visibility generation 1, with no
replacement request. Every opening recorded the same icon frame
`{{1277,1082},{27,22}}`; the control stayed available and all eight assigned apps
remained tucked. Current icon, assignments and behaviour preferences were retained.

## Menu bar tint placement — 0.1.5

The tint used an ordinary borderless panel, subject to AppKit's usable-desktop
frame constraints, and a fixed status-bar thickness. A dedicated mouse-transparent
TintPanel now permits placement inside the menu bar, takes the display's safe
area into account, and sits one level below status controls. The geometry cache
includes each display's menu bar height and safe area, so changes rebuild panels.

The signed release was installed in `/Applications/Nook.app`. With the owner's
14% teal tint enabled, the app recorded these actual frames after ordering front:

- MacBook display `{{0,0},{1710,1112}}`: tint `{{0,1074},{1710,38}}`, reaching
  the display top at 1112. AppKit rounds the requested 37.5-point height to 38.
- External display `{{-799,1112},{3440,1440}}`: tint `{{-799,2530},{3440,22}}`,
  reaching the display top at 2552.

Turning tint off and back on reproduced the same frames. Nook's status button
still tucked all eight assigned apps and opened/closed the shelf with tint enabled.
Twenty core tests passed; the tint, icon and organisation settings were preserved.
Native screenshot capture returned isolated overlay pixels rather than a composed
menu bar, so placement verification relies on the app's actual window geometry;
composed visual appearance across displays remains a physical check.

## Interface copy cleanup — 0.1.6

Removed the sidebar slogan and idle reassurance, promotional pane headings,
About slogans and badges, implementation history, and redundant appearance hints.
Pane headings now match their navigation labels. Groups are labelled Visible,
Hidden and Always hidden; actions, status messages, gestures and shortcut labels
use the same terminology. Saved enum values and preference keys are unchanged.
Permission and recovery instructions remain; controls have short descriptive
labels. Diagnostics remain available in a collapsed disclosure on About.

The signed release was installed in `/Applications/Nook.app`. All four settings
panes were reviewed with native screenshots, including the scrolled shortcut
section. Quick controls and the shelf were also reviewed. Labels fit without
clipping; Diagnostics expanded and collapsed; the renamed toggle hid all eight
assigned apps and the shelf opened and closed. The twenty existing core tests,
including preference compatibility and round-trip tests, passed. The permission
screen and error copy were reviewed in source, without revoking Accessibility.
Current preferences were retained, including the owner's now-disabled tint.

## Automatic updates — 0.1.7, 7 October 2026

Added Sparkle 2.10.0, daily checks, manual checks and optional automatic
download/installation controls. The application restores menu bar visibility
before update relaunch. Update settings use Sparkle's macOS preferences rather
than Nook's organisation JSON. The Nook Ed25519 private key is stored under
the `dev.nathanlanger.Nook` account in Keychain; only its public key is packaged.

Twenty core tests, three publishing policy tests and four feed-metadata tests
passed. Both ad-hoc development packaging and Developer ID packaging passed
recursive signature verification. Packaging removes SwiftPM's absolute
development framework search path and signs Sparkle's helpers inside-out.
An isolated test app and DMG were accepted by Apple, stapled and accepted by
Gatekeeper. The complete local release verifier passed, including ZIP contents,
permissions and symlink comparison, DMG verification, appcast metadata, and
Sparkle signatures. Modifying feed text or flipping an archive byte caused
signature verification to fail. Unconfigured release packaging was rejected.

Native UI checks confirmed About's update controls, the installation toggle's
disabled state until checks are enabled, persistence of both preferences in an
isolated test defaults domain, and manual-check recovery from an unavailable
server. The installed 0.1.6 app was reopened after testing and its previous nine
hidden apps were hidden again. The test copy was stopped.

The unavailable-server test used `updates.invalid` and was deliberately
unpublished. Production Space is configured: `nook-releases` in `lon1`, CDN enabled, restricted
listing, one-minute fallback edge cache TTL. The public configuration was saved
to `distribution/spaces.json`. The bucket-scoped `nook-release-publisher` key
was created with the owner's explicit approval and saved in the login Keychain.
Authenticated upload and metadata lookup succeeded. Two revisions of a small
validation object were verified byte-for-byte through origin and CDN; the CDN
returned the second revision immediately and preserved the live metadata cache
header (`no-cache, max-age=0, must-revalidate`). Bucket listing remains restricted.

The final 0.1.7 app and DMG were accepted by Apple, stapled and verified by
Gatekeeper. The complete release verifier passed. A notarized updater-enabled
test copy, labelled 0.1.6/build 7, was installed at `/Applications/Nook.app` with a
separate hosted test feed under `nook/validation/updater-2026-10-07/`. This is a
test copy of the new updater code, not the public 0.1.6 binary, which has no
updater. It downloaded the exact production 0.1.7 DMG through the CDN, verified
the signed feed and archive, installed and relaunched as version 0.1.7/build 8.
All nine hidden apps were restored during restart. Both Sparkle update settings
survived. Organisation, appearance and behaviour settings were unchanged; only
the remembered-app cache order changed. Launch at login remained enabled.

A second run from the same lower-build test copy exercised a scheduled check
with optional automatic installation enabled. Sparkle downloaded and staged the
update in the background. Normal quit installed build 8 and left Nook closed;
opening Nook then ran the production app. Accessibility remained granted and
all nine assigned apps could still be hidden. Automatic installation was
returned to its default off state; daily checks remain enabled. The final
installed app uses the production feed and the previous hidden state was restored.

The public source commit for this build is `0e97c71`. Version 0.1.7 was published
as a GitHub prerelease and to Spaces. The publisher verified all four release
files byte-for-byte through origin and CDN before advancing the signed production
feed. It verified the stable feed and `latest.json` afterward. A manual update
check from the installed production app displayed “You’re up to date!” for
0.1.7. Existing users of 0.1.6 need one manual installation to gain the updater.

## Visibility request handoff — 0.1.8, 7 October 2026

The visibility allow-list included every running app. Starting or stopping a
background helper changed that list, and replacing the request released the
old restriction followed by a 250 ms delay. That exposed hidden icons even
though the user's hidden assignments had not changed. The report from another
Mac has not been reproduced on that machine; this code path explains brief
show/hide flashes during app lifecycle changes.

Request replacement now retains the active restriction until its replacement
activates, then releases the previous restriction before verifying the result.
Errors and timeouts still restore every icon. Previously allowed bundle IDs
remain allowed after their processes exit, avoiding unnecessary replacement
on exit or return. New apps are allowed; explicit hidden assignments override
retained allow-list entries.

Twenty-two core tests passed, including regressions for background-app exit and
return, new apps, and reassignment of a previously allowed app. A Developer ID
build was installed for live testing. Hiding nine apps succeeded. Starting
Calculator caused one replacement while all nine remained hidden; quitting and
reopening Calculator retained the same request generation. With the shelf
temporarily disabled, a direct reveal showed the Hidden apps and retained the
Always hidden app's restriction; hiding again succeeded. The owner's shelf
preference was restored. These checks were on macOS 27.2 (26B5091g); the other
Mac's version and exact flash duration are still awaiting confirmation.

## Other coverage still needed

Global shortcut registration and delivery on a physical keyboard; hover,
scroll and empty-space gestures; shelf interaction; multi-display/notched
layouts; full-screen appearance; login startup; sleep/wake and crash recovery;
import/export panels; private API failure on other macOS builds. The native
automation tool's shortcut attempts did not trigger the old handler, so they
are not counted as passing global-shortcut tests. The final handler uses the
Carbon dispatcher and supports app-local key events. Control-Option-N worked
with Nook focused; an automated attempt from Figma did not change Nook's state.
Physical keyboard testing is still required for system-wide delivery.

Temporary fixture processes were stopped, fixture cards and the test Figma
assignment were removed, and automatic rehide was restored. Test choices did
not modify Figma's or Ice's preference files.
