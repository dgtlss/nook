#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

NOOK_RELEASE="${1:?Pass the completed release directory.}"
NOOK_RELEASE="$(cd "$NOOK_RELEASE" && pwd)"
NOOK_APP="$NOOK_RELEASE/work/Nook.app"
NOOK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$NOOK_APP/Contents/Info.plist)"
NOOK_TAG="v${NOOK_VERSION}"
NOOK_SOURCE="$(cat "$NOOK_RELEASE/verification/source-commit.txt")"
NOOK_ZIP="$NOOK_RELEASE/Nook-${NOOK_VERSION}-arm64.zip"
NOOK_DMG="$NOOK_RELEASE/Nook-${NOOK_VERSION}-arm64.dmg"

for NOOK_RECORD in app-notarization dmg-notarization; do
    /usr/bin/plutil -extract status raw -o - "$NOOK_RELEASE/verification/${NOOK_RECORD}.json" | /usr/bin/grep -qx Accepted
done
(cd "$NOOK_RELEASE" && shasum -a 256 -c SHA256SUMS.txt)
xcrun stapler validate "$NOOK_APP"
xcrun stapler validate "$NOOK_DMG"
codesign --verify --strict "$NOOK_APP"
codesign --verify --strict "$NOOK_DMG"
spctl --assess --type execute --verbose=4 "$NOOK_APP"
spctl --assess --type open --context context:primary-signature --verbose=4 "$NOOK_DMG"
hdiutil verify "$NOOK_DMG"

# Check the distributed ZIP, not just the source bundle used to create it.
NOOK_EXTRACT="$(mktemp -d "$PWD/build/nook-release-extract.XXXXXX")"
ditto -x -k "$NOOK_ZIP" "$NOOK_EXTRACT"
codesign --verify --strict "$NOOK_EXTRACT/Nook.app"
xcrun stapler validate "$NOOK_EXTRACT/Nook.app"
spctl --assess --type execute --verbose=4 "$NOOK_EXTRACT/Nook.app"

gh release view "$NOOK_TAG" --repo dgtlss/nook --json isDraft,tagName,targetCommitish \
    > "$NOOK_RELEASE/verification/github-draft.json"
test "$(/usr/bin/plutil -extract isDraft raw -o - "$NOOK_RELEASE/verification/github-draft.json")" = true
test "$(/usr/bin/plutil -extract tagName raw -o - "$NOOK_RELEASE/verification/github-draft.json")" = "$NOOK_TAG"
test "$(/usr/bin/plutil -extract targetCommitish raw -o - "$NOOK_RELEASE/verification/github-draft.json")" = "$NOOK_SOURCE"

# No clobber flag: an existing asset is never silently replaced.
gh release upload "$NOOK_TAG" --repo dgtlss/nook "$NOOK_DMG" "$NOOK_ZIP" "$NOOK_RELEASE/SHA256SUMS.txt"
gh release view "$NOOK_TAG" --repo dgtlss/nook --json assets > "$NOOK_RELEASE/verification/github-assets.json"
test "$(/usr/bin/plutil -extract assets raw -o - "$NOOK_RELEASE/verification/github-assets.json" 2>/dev/null | wc -l | tr -d ' ')" != 0
gh release edit "$NOOK_TAG" --repo dgtlss/nook --draft=false --prerelease --latest=false
gh release view "$NOOK_TAG" --repo dgtlss/nook --json url,isDraft,isPrerelease,tagName,assets \
    > "$NOOK_RELEASE/verification/published-release.json"
test "$(/usr/bin/plutil -extract isDraft raw -o - "$NOOK_RELEASE/verification/published-release.json")" = false
printf 'Published: https://github.com/dgtlss/nook/releases/tag/%s\n' "$NOOK_TAG"
