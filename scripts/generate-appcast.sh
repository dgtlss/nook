#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
NOOK_RELEASE="$(cd "${1:?Pass the completed release directory.}" && pwd)"
NOOK_PLIST="$NOOK_RELEASE/work/Nook.app/Contents/Info.plist"
NOOK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$NOOK_PLIST")"
NOOK_FEED="$(/usr/libexec/PlistBuddy -c 'Print SUFeedURL' "$NOOK_PLIST")"
NOOK_KEY="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$NOOK_PLIST")"
NOOK_TOOLS="$PWD/.build/artifacts/sparkle/Sparkle/bin"
test "$("$NOOK_TOOLS/generate_keys" --account dev.nathanlanger.Nook -p)" = "$NOOK_KEY"
mkdir -p "$NOOK_RELEASE/work/updates"
cp "$NOOK_RELEASE/Nook-${NOOK_VERSION}-arm64.dmg" "$NOOK_RELEASE/work/updates/"
"$NOOK_TOOLS/generate_appcast" --account dev.nathanlanger.Nook \
    --maximum-deltas 0 --download-url-prefix "${NOOK_FEED%/*}/versions/v${NOOK_VERSION}/" \
    --link https://github.com/dgtlss/nook \
    -o "$NOOK_RELEASE/appcast.xml" "$NOOK_RELEASE/work/updates"
"$NOOK_TOOLS/sign_update" --account dev.nathanlanger.Nook --verify "$NOOK_RELEASE/appcast.xml"
/usr/bin/python3 scripts/verify-update.py "$NOOK_RELEASE" > "$NOOK_RELEASE/verification/update-manifest.json"
