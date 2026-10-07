#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
NOOK_RELEASE="$(cd "${1:?Pass the completed release directory.}" && pwd)"
NOOK_APP="$NOOK_RELEASE/work/Nook.app"
NOOK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$NOOK_APP/Contents/Info.plist")"
NOOK_ZIP="$NOOK_RELEASE/Nook-${NOOK_VERSION}-arm64.zip"
NOOK_DMG="$NOOK_RELEASE/Nook-${NOOK_VERSION}-arm64.dmg"
for NOOK_RECORD in app-notarization dmg-notarization; do
    /usr/bin/plutil -extract status raw -o - "$NOOK_RELEASE/verification/${NOOK_RECORD}.json" | /usr/bin/grep -qx Accepted
done
(cd "$NOOK_RELEASE" && shasum -a 256 -c SHA256SUMS.txt)
xcrun stapler validate "$NOOK_APP"
xcrun stapler validate "$NOOK_DMG"
codesign --verify --deep --strict "$NOOK_APP"
codesign --verify --strict "$NOOK_DMG"
spctl --assess --type execute --verbose=4 "$NOOK_APP"
spctl --assess --type open --context context:primary-signature --verbose=4 "$NOOK_DMG"
hdiutil verify "$NOOK_DMG"
NOOK_EXTRACT="$(mktemp -d "$PWD/build/nook-release-extract.XXXXXX")"
trap 'rm -rf "$NOOK_EXTRACT"' EXIT
ditto -x -k "$NOOK_ZIP" "$NOOK_EXTRACT"
codesign --verify --deep --strict "$NOOK_EXTRACT/Nook.app"
xcrun stapler validate "$NOOK_EXTRACT/Nook.app"
spctl --assess --type execute --verbose=4 "$NOOK_EXTRACT/Nook.app"
/usr/bin/python3 - "$NOOK_APP" "$NOOK_EXTRACT/Nook.app" <<'PY'
import hashlib, os, stat, sys
from pathlib import Path

def contents(root):
    result = {}
    for base, directories, files in os.walk(root, followlinks=False):
        for name in directories + files:
            path = Path(base) / name
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                value = ('link', os.readlink(path))
            elif stat.S_ISREG(mode):
                value = ('file', mode & 0o777, hashlib.sha256(path.read_bytes()).hexdigest())
            elif stat.S_ISDIR(mode):
                value = ('directory',)
            else:
                sys.exit('Unexpected file type in application bundle')
            result[str(path.relative_to(root))] = value
    return result

if contents(Path(sys.argv[1])) != contents(Path(sys.argv[2])):
    sys.exit('Distributed ZIP contents differ from the verified application')
PY
if [[ -f "$NOOK_RELEASE/appcast.xml" ]]; then
    NOOK_TOOLS="$PWD/.build/artifacts/sparkle/Sparkle/bin"
    NOOK_KEY="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$NOOK_APP/Contents/Info.plist")"
    test "$("$NOOK_TOOLS/generate_keys" --account dev.nathanlanger.Nook -p)" = "$NOOK_KEY"
    "$NOOK_TOOLS/sign_update" --account dev.nathanlanger.Nook --verify "$NOOK_RELEASE/appcast.xml"
    /usr/bin/python3 scripts/verify-update.py "$NOOK_RELEASE" > "$NOOK_RELEASE/verification/update-manifest.json"
    NOOK_ED_SIGNATURE="$(/usr/bin/plutil -extract archiveSignature raw -o - "$NOOK_RELEASE/verification/update-manifest.json")"
    "$NOOK_TOOLS/sign_update" --account dev.nathanlanger.Nook --verify "$NOOK_DMG" "$NOOK_ED_SIGNATURE"
else
    printf 'Missing signed appcast. Prepare a complete update release.\n' >&2
    exit 1
fi
