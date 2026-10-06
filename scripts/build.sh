#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
NOOK_CONFIGURATION="${NOOK_CONFIGURATION:-debug}"
swift build -c "$NOOK_CONFIGURATION"
NOOK_BIN_DIR="$(swift build -c "$NOOK_CONFIGURATION" --show-bin-path)"
mkdir -p build
NOOK_STAGE="$(mktemp -d "$PWD/build/nook-package.XXXXXX")"
NOOK_BUNDLE="$NOOK_STAGE/Nook.app"
mkdir -p "$NOOK_BUNDLE/Contents/MacOS" "$NOOK_BUNDLE/Contents/Resources"
cp "$NOOK_BIN_DIR/Nook" "$NOOK_BUNDLE/Contents/MacOS/Nook"
cp Resources/Info.plist "$NOOK_BUNDLE/Contents/Info.plist"
if [[ -f Resources/Nook.icns ]]; then
    cp Resources/Nook.icns "$NOOK_BUNDLE/Contents/Resources/Nook.icns"
fi
cp LICENSE "$NOOK_BUNDLE/Contents/Resources/LICENSE"
codesign --force --options runtime --timestamp=none --sign "${NOOK_SIGN_IDENTITY:--}" "$NOOK_BUNDLE"
codesign --verify --strict "$NOOK_BUNDLE"
if [[ -d "$PWD/build/Nook.app" ]]; then
    mv "$PWD/build/Nook.app" "$NOOK_STAGE/previous-Nook.app"
fi
mv "$NOOK_BUNDLE" "$PWD/build/Nook.app"
printf 'Built %s\n' "$PWD/build/Nook.app"
printf 'Quit and reopen Nook to run the new build. Previous build retained in %s\n' "$NOOK_STAGE"
