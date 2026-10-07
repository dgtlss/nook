# Nook

Nook is an open-source macOS menu bar manager, written in Swift, SwiftUI and a small Objective-C bridge. MIT licensed, with no tracking.
Updates use the open-source [Sparkle](https://sparkle-project.org) framework.

Nook's source, interface and artwork were created for this project. Ice was a
reference for user-facing features. No Ice source or assets are included. See
[provenance](docs/PROVENANCE.md).

## Download

Preview downloads are published through [GitHub Releases](https://github.com/dgtlss/nook/releases).
Packaged builds target Apple silicon and macOS 27 or later; macOS 27.2
(26B5091g) is the tested build. Use the DMG to install Nook in Applications.

## Run

Install and run `/Applications/Nook.app` (see Build below). Enable it in System Settings →
Privacy & Security → Accessibility. Nook uses Accessibility to discover status
items and activate their menus. Screen Recording is not required.

In Organise, move apps to **Hidden** or **Always hidden** using drag and
drop or each card's menu. Nook's selected icon stays in the menu bar. Click it
to show hidden apps, then click again to hide them. A click reveal stays
open until the next click, even when timed rehide is enabled. Option-click
shows everything; right-click opens quick controls and search.

- Hidden apps return when toggled.
- Always hidden apps return on Show all, or when explicitly selected in search.
- Apps you haven't assigned remain visible.
- Apps with multiple status items move together.
- Command-drag status items in macOS to change their physical order. Card order
  controls Nook's own shelf and search, not the native bar.

Shortcuts: Control-Option-N toggles, Control-Option-Space opens search, and
Control-Option-Shift-N shows all. Behaviour includes timed rehide, hover,
scroll, empty-space click, an app-icon shelf and launch at login. Appearance
includes five menu bar icon choices (Nook, Dot, Chevron, Leaf and Tiles), tint,
shape, border and shadow. The chosen icon is saved and takes effect immediately.
The whole icon tile is clickable. The shelf opens directly beneath the menu
bar on Nook's display, stays within that display's edges, and supports Escape
to dismiss it.
Preferences can be exported/imported
as JSON; they live in `~/Library/Application Support/Nook/preferences.json`.

On launch Nook starts with everything visible. **Reopening Nook from Finder or
your launcher also shows all apps and recreates its menu bar control.** This
recovery route does not depend on the icon or a global shortcut.

The control uses a stable autosave name and cannot be Command-dragged out of
the menu bar. Its native visibility and on-screen position are checked before
hiding. After changes and during the three-second refresh Nook also checks
that MenuBarAgent still hosts its own participant. If the control
becomes unavailable, Nook releases its visibility request and cancels automatic
rehide. Normal quit and sleep also release requests. Any verification failure
restores the bar and displays a message.

## Build

Requires macOS 27 and Xcode 27 with command line tools selected.

```sh
swift test
./scripts/build.sh
# Quit Nook before replacing the installed application.
./scripts/install.sh
```

By default the app is ad-hoc signed for development. Production updates require
`distribution/spaces.json`, configured as described in [Releasing](docs/RELEASING.md).
To use your own signing identity:

```sh
NOOK_CONFIGURATION=release NOOK_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./scripts/build.sh
```

This builds locally. Developer ID builds use hardened runtime and a secure
timestamp; ad-hoc development builds have no secure timestamp or hardened runtime.
Sparkle and its helpers are embedded and signed inside-out. To prepare notarized ZIP and
DMG downloads, follow [Releasing](docs/RELEASING.md).
Open `/Applications/Nook.app` after installation. On the tested macOS build,
launching from the development folder caused the system allow-list to hide
Nook itself despite explicitly allowing its bundle ID. The installed copy
retained its toggle. Development-folder launches now keep all apps visible
and explain that installation is required. Previous installed builds are
retained under `build/previous-install.*`.
`scripts/build-fixtures.sh` builds two original disposable menu bar apps for
integration testing. No existing application's preferences need to be altered.

## Current scope

Version 0.1.7 is an experimental preview. It targets the installed
macOS 27.2 build 26B5091g. The visibility backend uses the private Apple
`MenuBarClientCore` framework, checks selectors at runtime, and verifies actual
Accessibility visibility after each hide/peek request. Apple can change this
interface; support on other builds is unverified. This backend is unsuitable
for a Mac App Store submission.

The development fixtures failed to return through Apple's allow-list while a
restriction was active; installed Figma did return correctly. An app with this
compatibility problem causes Nook to release its request and restore the bar.
See the validation record for the exact observations.

This first version does not yet match every Ice feature: the shelf uses app
icons rather than copies of each status glyph; native icon spacing, automatic
physical rearrangement, gradient backgrounds and app-menu overflow handling
are not implemented. Launch at login, all gestures,
full-screen appearance, multiple displays and sleep/wake need broader testing.

See [validation](docs/VALIDATION.md) for tested behavior and remaining coverage.
The source and artwork are distributed under MIT. For release downloads and
checksums, see GitHub Releases.

## Updates

Configured distribution builds check daily over HTTPS. **About Nook → Updates**
includes a manual check and controls for automatic checks and installation.
Automatic installation is optional and initially off; when enabled, Sparkle can
install a downloaded update when Nook quits, or prompt for a restart later.
Nook restores hidden menu bar apps before restarting. Update settings are stored
by Sparkle in macOS preferences, separately from Nook's exported organisation settings.

Update feeds and DMGs are signed with Ed25519; the app and DMG are also Developer ID
signed and notarized. Feed signatures and archive signatures are verified before
extraction. The update server receives ordinary download requests, without Sparkle
system profiling. Builds without a feed show “Updates are not configured in this build.”
Version 0.1.6 and earlier need one manual upgrade to gain the updater.

## Contributing

Keep implementation original. Use Apple documentation, installed system API
metadata and observed behavior as references. Do not copy other menu bar
managers' code or artwork. Include the macOS version/build with bug reports,
describe expected/observed icon visibility, and avoid attaching private app
menu contents. Changes to the private backend need live hide, peek, show-all
and quit-restoration testing as well as the core policy tests.
