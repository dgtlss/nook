# Direct distribution

Releases are prepared locally with Xcode and an existing Developer ID Application
identity. Signing keys and notarization credentials remain in Keychain.

## Configure updates

Production hosting is configured in `distribution/spaces.json`: the
`nook-releases` Space in London (`lon1`), with CDN origin
`https://nook-releases.lon1.cdn.digitaloceanspaces.com` and the `nook/` prefix.
Bucket listing is restricted. The CDN's fallback edge cache TTL is one minute;
the publisher sets cache headers separately on immutable downloads and live
metadata. The production feed URL is
`https://nook-releases.lon1.cdn.digitaloceanspaces.com/nook/appcast.xml`.

Use Node.js 22+ and the Python 3 supplied with Xcode's command line tools for the
publishing scripts. Copy `distribution/spaces.example.json` to
`distribution/spaces.json` and set the bucket, region, CDN origin and an isolated
prefix. This file contains public hosting details and can be committed. Enable
the Space's CDN; keep bucket listing private. Only release objects need public
read access. CORS is not needed for the native updater.

Run `npm ci --prefix scripts/update-publisher`. The application uses the pinned
Sparkle binary from Swift Package Manager; the JavaScript dependencies are only
for release publishing.

Local checks: `swift test`, `npm test --prefix scripts/update-publisher`, and
`/usr/bin/python3 scripts/test-verify-update.py`.

Generate an update signing key once:

```sh
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account dev.nathanlanger.Nook
```

The private Ed25519 key stays in Keychain; put only its public key in
`SUPublicEDKey` in `Resources/Info.plist`. Preserve a secure backup independently
of the CDN. Do not generate a replacement key for each release. For this project
the Nook-specific key is already generated on the development Mac.

The build reads the feed URL from `distribution/spaces.json`; an explicit
`NOOK_UPDATE_FEED_URL` can override it for separate test builds. Never publish a
test build to the production feed. Release builds require an HTTPS feed URL.
Unconfigured debug builds disable updates. Credentials and private signing keys
must never be added to the hosting config, source, app bundle or release assets.

```sh
NOOK_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOOK_NOTARY_PROFILE='your-saved-notarytool-profile' ./scripts/release.sh
```

The script runs the core tests, builds an optimized Apple silicon app, signs it
with hardened runtime and a secure timestamp, and submits it to Apple. It requires
acceptance, staples the app ticket, and checks Gatekeeper before creating the ZIP.
It also creates a drag-to-Applications DMG, signs and notarizes that image, staples
its ticket, and checks Gatekeeper again. The release directory contains final
downloads, a signed appcast, SHA-256 checksums, and local verification records.
Sparkle signs the final stapled DMG and appcast using the Nook Keychain account;
the script checks the public key matches the packaged app. No credentials are
embedded in the app or uploaded with the source.
The working tree must be clean so the release's recorded source commit matches
the packaged code and public hosting configuration.

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
Release with the DMG, ZIP, `appcast.xml` and `SHA256SUMS.txt`. For this repository, prepare a
draft with the exact source commit recorded in `verification/source-commit.txt`,
then run `./scripts/publish-release.sh <release-directory>` to recheck the
notarization records, downloads, extracted ZIP and Gatekeeper before uploading
and publishing. Existing assets are never overwritten. Mark experimental versions as
pre-releases and state the tested macOS build and architecture. Do not upload
the working directory or signing diagnostics as release assets.

## Publish to Spaces

On the release Mac, the `nook-release-publisher` key is stored in the login
Keychain under `dev.nathanlanger.Nook.Spaces`. It is limited to Read/Write/Delete
on `nook-releases`. The publisher reads it directly from Keychain. To configure
another Mac, create an appropriately scoped key and run
`python3 scripts/store-spaces-credentials.py`; both inputs are hidden. The helper
passes credentials through a pipe to the Security framework, never as command
arguments. This credential is used only by release tooling, never by Nook.app.

Alternatively, set both `SPACES_ACCESS_KEY_ID` and `SPACES_SECRET_ACCESS_KEY` in
your local environment. Do not put secrets in command arguments, source or chat.
Then run:

```sh
node scripts/update-publisher/publish.mjs build/releases/v0.1.7.XXXXXX
```

The publisher rechecks Apple's notarization results, Gatekeeper, both packaged
downloads, checksums, Sparkle feed signatures, DMG signatures and feed metadata.
It uploads immutable files under `<prefix>/versions/v<version>/` and verifies
their full SHA-256 hashes through both origin and CDN before advancing
`<prefix>/appcast.xml`. `latest.json` supplies the latest version, download URL
and checksum for a website or download link.

Versioned files use a one-year immutable cache. The live feed and `latest.json`
use `no-cache, max-age=0, must-revalidate`; configure the CDN to respect these
headers. Verify the exact stable CDN feed URL after publishing. If the CDN
overrides caching, fix that setting and purge the cached feed before retrying.
Never edit a signed XML feed after generation: its signature covers the bytes.
Keep the feed URL stable once a build ships.

Published files cannot be silently replaced and the feed cannot be rolled back
to a lower build. Identical retries are allowed; changed files require a new
version. Use one publishing machine/process. Spaces does not document
conditional object PUTs; a local lock and an ETag recheck protect this workflow
from accidental concurrent runs, but do not provide a distributed lock. A crash
can leave `build/spaces-publish.lock`; remove it only after confirming no publisher
is running. Upload failures leave the old feed available. If the feed upload
succeeds and later CDN verification fails, inspect the live feed before retrying.

## Validate the updater

Before shipping the first update-enabled release, use a separate HTTPS test feed
to verify old-to-new installation and relaunch, a corrupted archive, a modified
feed, an unavailable server, and both automatic-update settings. Do not use high
test build numbers in the production feed. Confirm menu bar items are restored
on restart, preferences and launch-at-login survive, Accessibility remains
granted, and the updated app runs from Applications. A successful build or a
signed feed alone does not verify installation. Existing 0.1.6 users need one
manual installation of 0.1.7 before Sparkle can deliver future releases.

Apple's [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
describes signing, submission and stapling. Nook uses a private Apple framework,
so this workflow is for direct distribution rather than the Mac App Store.
