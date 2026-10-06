#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
for NOOK_FIXTURE in A B; do
    NOOK_FIXTURE_PATH="$PWD/build/Nook Test $NOOK_FIXTURE.app"
    mkdir -p "$NOOK_FIXTURE_PATH/Contents/MacOS"
    xcrun swiftc -parse-as-library -target arm64-apple-macos27.0 tools/test-fixture.swift -o "$NOOK_FIXTURE_PATH/Contents/MacOS/NookFixture$NOOK_FIXTURE"
    cat > "$NOOK_FIXTURE_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Nook Test $NOOK_FIXTURE</string>
<key>CFBundleIdentifier</key><string>dev.nathanlanger.Nook.Fixture$NOOK_FIXTURE</string>
<key>CFBundleExecutable</key><string>NookFixture$NOOK_FIXTURE</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>27.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF
    codesign --force --options runtime --timestamp=none --sign "${NOOK_SIGN_IDENTITY:--}" "$NOOK_FIXTURE_PATH"
done
