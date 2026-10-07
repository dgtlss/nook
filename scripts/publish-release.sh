#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

NOOK_RELEASE="${1:?Pass the completed release directory.}"
NOOK_RELEASE="$(cd "$NOOK_RELEASE" && pwd)"
NOOK_APP="$NOOK_RELEASE/work/Nook.app"
NOOK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$NOOK_APP/Contents/Info.plist")"
NOOK_TAG="v${NOOK_VERSION}"
NOOK_SOURCE="$(cat "$NOOK_RELEASE/verification/source-commit.txt")"
NOOK_ZIP="$NOOK_RELEASE/Nook-${NOOK_VERSION}-arm64.zip"
NOOK_DMG="$NOOK_RELEASE/Nook-${NOOK_VERSION}-arm64.dmg"

./scripts/verify-release.sh "$NOOK_RELEASE"

gh release view "$NOOK_TAG" --repo dgtlss/nook --json isDraft,tagName,targetCommitish \
    > "$NOOK_RELEASE/verification/github-draft.json"
test "$(/usr/bin/plutil -extract isDraft raw -o - "$NOOK_RELEASE/verification/github-draft.json")" = true
test "$(/usr/bin/plutil -extract tagName raw -o - "$NOOK_RELEASE/verification/github-draft.json")" = "$NOOK_TAG"
test "$(/usr/bin/plutil -extract targetCommitish raw -o - "$NOOK_RELEASE/verification/github-draft.json")" = "$NOOK_SOURCE"

# No clobber flag: an existing asset is never silently replaced.
gh release upload "$NOOK_TAG" --repo dgtlss/nook "$NOOK_DMG" "$NOOK_ZIP" "$NOOK_RELEASE/SHA256SUMS.txt" "$NOOK_RELEASE/appcast.xml"
gh release view "$NOOK_TAG" --repo dgtlss/nook --json assets > "$NOOK_RELEASE/verification/github-assets.json"
python3 - "$NOOK_RELEASE" "$NOOK_VERSION" <<'PY'
import json, sys
from pathlib import Path
release, version = Path(sys.argv[1]), sys.argv[2]
names = [f'Nook-{version}-arm64.dmg', f'Nook-{version}-arm64.zip', 'SHA256SUMS.txt', 'appcast.xml']
expected = {name: (release / name).stat().st_size for name in names}
assets = json.loads((release / 'verification/github-assets.json').read_text())['assets']
actual = {asset['name']: asset['size'] for asset in assets}
assert len(assets) == 4 and actual == expected, 'Uploaded release assets do not match the verified files'
PY
gh release edit "$NOOK_TAG" --repo dgtlss/nook --draft=false --prerelease --latest=false
gh release view "$NOOK_TAG" --repo dgtlss/nook --json url,isDraft,isPrerelease,tagName,assets \
    > "$NOOK_RELEASE/verification/published-release.json"
test "$(/usr/bin/plutil -extract isDraft raw -o - "$NOOK_RELEASE/verification/published-release.json")" = false
printf 'Published: https://github.com/dgtlss/nook/releases/tag/%s\n' "$NOOK_TAG"
