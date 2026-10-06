# Direct distribution

Releases are prepared locally with Xcode and an existing Developer ID Application
identity. Signing keys and notarization credentials remain in Keychain.

```sh
NOOK_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOOK_NOTARY_PROFILE='your-saved-notarytool-profile' ./scripts/release.sh
```

The script runs the core tests, builds an optimized Apple silicon app, signs it
with hardened runtime and a secure timestamp, and submits it to Apple. It requires
acceptance, staples the app ticket, and checks Gatekeeper before creating the ZIP.
It also creates a drag-to-Applications DMG, signs and notarizes that image, staples
its ticket, and checks Gatekeeper again. The release directory contains final
downloads, SHA-256 checksums, and local verification records. No credentials are
embedded in the app or uploaded with the source.

Outputs go into a fresh `build/releases/v<version>.*` directory. Do not overwrite
a published version. Increase the bundle version and public version before
preparing a later release. The script does not publish or change repository
visibility automatically. Do not publish downloads unless every verification
step completes successfully.

Notarization can take time. If interrupted, retain the release directory and
submission ID; query that submission with `notarytool info` or `notarytool wait`
using the same Keychain profile instead of immediately resubmitting. Fetch the
notarization log on rejection and correct the cause before preparing new files.

Before publishing, inspect the exact source commit, verify the final checksums,
and test installation from the archive. Tag that commit and create a GitHub
Release with the DMG, ZIP and `SHA256SUMS.txt`. Mark experimental versions as
pre-releases and state the tested macOS build and architecture. Do not upload
the working directory or signing diagnostics as release assets.

Apple's [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
describes signing, submission and stapling. Nook uses a private Apple framework,
so this workflow is for direct distribution rather than the Mac App Store.
