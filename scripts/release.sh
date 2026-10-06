#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Credentials remain in Keychain. This script prepares downloads; publishing
# them is a separate step after reviewing the release notes and source.
: "${NOOK_SIGN_IDENTITY:?Set NOOK_SIGN_IDENTITY to your Developer ID Application identity.}"
: "${NOOK_NOTARY_PROFILE:?Set NOOK_NOTARY_PROFILE to an existing notarytool Keychain profile.}"
if [[ "$NOOK_SIGN_IDENTITY" != 'Developer ID Application:'* ]]; then
    printf 'A Developer ID Application identity is required.\n' >&2
    exit 1
fi

swift test
NOOK_CONFIGURATION=release ./scripts/build.sh
NOOK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/Nook.app/Contents/Info.plist)"
NOOK_ARCH="$(lipo -archs build/Nook.app/Contents/MacOS/Nook)"
if [[ "$NOOK_ARCH" != arm64 ]]; then
    printf 'This release workflow currently supports the tested arm64 build only.\n' >&2
    exit 1
fi
mkdir -p build/releases
NOOK_RELEASE="$(mktemp -d "$PWD/build/releases/v${NOOK_VERSION}.XXXXXX")"
mkdir -p "$NOOK_RELEASE/work" "$NOOK_RELEASE/verification"
printf 'Release directory: %s\n' "$NOOK_RELEASE"
git rev-parse HEAD > "$NOOK_RELEASE/verification/source-commit.txt"
ditto build/Nook.app "$NOOK_RELEASE/work/Nook.app"
NOOK_APP="$NOOK_RELEASE/work/Nook.app"
codesign --verify --strict "$NOOK_APP"
codesign -d --verbose=4 "$NOOK_APP" 2> "$NOOK_RELEASE/verification/app-signature.txt"
if ! /usr/bin/grep -q '^Timestamp=' "$NOOK_RELEASE/verification/app-signature.txt"; then
    printf 'The app signature has no secure timestamp.\n' >&2
    exit 1
fi

require_accepted() {
    /usr/bin/plutil -extract status raw -o - "$1" | /usr/bin/grep -qx Accepted
}

ditto -c -k --sequesterRsrc --keepParent "$NOOK_APP" "$NOOK_RELEASE/work/app-submission.zip"
xcrun notarytool submit "$NOOK_RELEASE/work/app-submission.zip" \
    --keychain-profile "$NOOK_NOTARY_PROFILE" --wait --output-format json \
    > "$NOOK_RELEASE/verification/app-notarization.json"
require_accepted "$NOOK_RELEASE/verification/app-notarization.json"
xcrun stapler staple "$NOOK_APP"
xcrun stapler validate "$NOOK_APP" > "$NOOK_RELEASE/verification/app-staple.txt"
codesign --verify --strict "$NOOK_APP"
spctl --assess --type execute --verbose=4 "$NOOK_APP" 2> "$NOOK_RELEASE/verification/app-gatekeeper.txt"

NOOK_ZIP="$NOOK_RELEASE/Nook-${NOOK_VERSION}-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$NOOK_APP" "$NOOK_ZIP"
mkdir -p "$NOOK_RELEASE/work/disk"
ditto "$NOOK_APP" "$NOOK_RELEASE/work/disk/Nook.app"
ln -s /Applications "$NOOK_RELEASE/work/disk/Applications"
cat > "$NOOK_RELEASE/work/disk/Install.txt" <<'INSTALL'
Nook — macOS menu bar manager

Requires an Apple silicon Mac running macOS 27 or later.
This preview has been tested on macOS 27.2 (26B5091g).

1. Drag Nook into Applications.
2. Open Nook from Applications.
3. Enable Nook in System Settings > Privacy & Security > Accessibility.

Nook must run from Applications to hide menu bar apps reliably.
Click its menu bar icon to toggle hidden apps. Option-click shows all apps.
If its icon becomes unavailable, reopen Nook from Applications to show all apps.

Source and licence: https://github.com/dgtlss/nook
INSTALL
NOOK_DMG="$NOOK_RELEASE/Nook-${NOOK_VERSION}-arm64.dmg"
hdiutil create -volname "Nook ${NOOK_VERSION}" -srcfolder "$NOOK_RELEASE/work/disk" \
    -format UDZO "$NOOK_DMG"
codesign --force --timestamp --sign "$NOOK_SIGN_IDENTITY" "$NOOK_DMG"
codesign --verify --strict "$NOOK_DMG"
xcrun notarytool submit "$NOOK_DMG" --keychain-profile "$NOOK_NOTARY_PROFILE" \
    --wait --output-format json > "$NOOK_RELEASE/verification/dmg-notarization.json"
require_accepted "$NOOK_RELEASE/verification/dmg-notarization.json"
xcrun stapler staple "$NOOK_DMG"
xcrun stapler validate "$NOOK_DMG" > "$NOOK_RELEASE/verification/dmg-staple.txt"
codesign --verify --strict "$NOOK_DMG"
spctl --assess --type open --context context:primary-signature --verbose=4 "$NOOK_DMG" \
    2> "$NOOK_RELEASE/verification/dmg-gatekeeper.txt"

(cd "$NOOK_RELEASE" && shasum -a 256 "Nook-${NOOK_VERSION}-arm64.zip" "Nook-${NOOK_VERSION}-arm64.dmg" > SHA256SUMS.txt)
printf 'Verified downloads ready in %s\n' "$NOOK_RELEASE"
