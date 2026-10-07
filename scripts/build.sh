#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
NOOK_CONFIGURATION="${NOOK_CONFIGURATION:-debug}"
if [[ -z "${NOOK_UPDATE_FEED_URL:-}" && -f distribution/spaces.json ]]; then
    NOOK_UPDATE_FEED_URL="$(node scripts/spaces-config.mjs)"
fi
swift build -c "$NOOK_CONFIGURATION"
NOOK_BIN_DIR="$(swift build -c "$NOOK_CONFIGURATION" --show-bin-path)"
mkdir -p build
NOOK_STAGE="$(mktemp -d "$PWD/build/nook-package.XXXXXX")"
NOOK_BUNDLE="$NOOK_STAGE/Nook.app"
mkdir -p "$NOOK_BUNDLE/Contents/MacOS" "$NOOK_BUNDLE/Contents/Resources"
cp "$NOOK_BIN_DIR/Nook" "$NOOK_BUNDLE/Contents/MacOS/Nook"
# SwiftPM adds an absolute development framework search path before our bundle
# path. Remove it so packaged apps load only their signed embedded framework.
if otool -l "$NOOK_BUNDLE/Contents/MacOS/Nook" | /usr/bin/grep -Fq "$NOOK_BIN_DIR/PackageFrameworks"; then
    install_name_tool -delete_rpath "$NOOK_BIN_DIR/PackageFrameworks" "$NOOK_BUNDLE/Contents/MacOS/Nook"
fi
cp Resources/Info.plist "$NOOK_BUNDLE/Contents/Info.plist"
if [[ -n "${NOOK_UPDATE_FEED_URL:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Add SUFeedURL string $NOOK_UPDATE_FEED_URL" "$NOOK_BUNDLE/Contents/Info.plist"
fi
if [[ "$NOOK_CONFIGURATION" == release ]]; then
    /usr/bin/plutil -extract SUFeedURL raw -o - "$NOOK_BUNDLE/Contents/Info.plist" | /usr/bin/grep -Eq '^https://[^/]+/.+\.xml$' || {
        printf 'Set NOOK_UPDATE_FEED_URL to the production HTTPS appcast URL before building a release.\n' >&2
        exit 1
    }
fi
if [[ -f Resources/Nook.icns ]]; then
    cp Resources/Nook.icns "$NOOK_BUNDLE/Contents/Resources/Nook.icns"
fi
cp LICENSE "$NOOK_BUNDLE/Contents/Resources/LICENSE"
NOOK_SPARKLE_ROOT="$PWD/.build/artifacts/sparkle/Sparkle"
NOOK_FRAMEWORK="$NOOK_BUNDLE/Contents/Frameworks/Sparkle.framework"
mkdir -p "$NOOK_BUNDLE/Contents/Frameworks"
ditto "$NOOK_SPARKLE_ROOT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$NOOK_FRAMEWORK"
cp "$NOOK_SPARKLE_ROOT/LICENSE" "$NOOK_BUNDLE/Contents/Resources/Sparkle-LICENSE.txt"
NOOK_IDENTITY="${NOOK_SIGN_IDENTITY:--}"
NOOK_CODESIGN=(--force --options runtime --timestamp)
if [[ "$NOOK_IDENTITY" == '-' ]]; then
    # Ad-hoc development bundles have no team identity for library validation.
    NOOK_CODESIGN=(--force --timestamp=none)
fi
# Sign nested code inside-out; never use --deep to sign a release.
for NOOK_NESTED in \
    "$NOOK_FRAMEWORK/Versions/B/Autoupdate" \
    "$NOOK_FRAMEWORK/Versions/B/Updater.app" \
    "$NOOK_FRAMEWORK/Versions/B/XPCServices/Downloader.xpc" \
    "$NOOK_FRAMEWORK/Versions/B/XPCServices/Installer.xpc" \
    "$NOOK_FRAMEWORK" \
    "$NOOK_BUNDLE"; do
    codesign "${NOOK_CODESIGN[@]}" --preserve-metadata=entitlements --sign "$NOOK_IDENTITY" "$NOOK_NESTED"
done
codesign --verify --deep --strict "$NOOK_BUNDLE"
if [[ -d "$PWD/build/Nook.app" ]]; then
    mv "$PWD/build/Nook.app" "$NOOK_STAGE/previous-Nook.app"
fi
mv "$NOOK_BUNDLE" "$PWD/build/Nook.app"
printf 'Built %s\n' "$PWD/build/Nook.app"
printf 'Quit and reopen Nook to run the new build. Previous build retained in %s\n' "$NOOK_STAGE"
