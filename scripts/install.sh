#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
NOOK_SOURCE="$PWD/build/Nook.app"
NOOK_TARGET="/Applications/Nook.app"
test -d "$NOOK_SOURCE"
codesign --verify --strict "$NOOK_SOURCE"
if pgrep -x Nook >/dev/null; then
    printf 'Quit Nook before installing the updated build.\n' >&2
    exit 1
fi
if [[ -e "$NOOK_TARGET" ]]; then
    NOOK_EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$NOOK_TARGET/Contents/Info.plist")"
    if [[ "$NOOK_EXISTING_ID" != 'dev.nathanlanger.Nook' ]]; then
        printf 'An unrelated app already occupies %s.\n' "$NOOK_TARGET" >&2
        exit 1
    fi
fi
NOOK_STAGE="$(mktemp -d /Applications/nook-install.XXXXXX)"
ditto "$NOOK_SOURCE" "$NOOK_STAGE/Nook.app"
codesign --verify --strict "$NOOK_STAGE/Nook.app"
if [[ -e "$NOOK_TARGET" ]]; then
    NOOK_BACKUP="$(mktemp -d "$PWD/build/previous-install.XXXXXX")"
    mv "$NOOK_TARGET" "$NOOK_BACKUP/Nook.app"
fi
mv "$NOOK_STAGE/Nook.app" "$NOOK_TARGET"
rmdir "$NOOK_STAGE"
printf 'Installed %s. Open this copy to use Nook.\n' "$NOOK_TARGET"
