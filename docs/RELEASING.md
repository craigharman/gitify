# Releasing Gitify

Gitify builds as a SwiftPM package (no Xcode required). The release pipeline produces a
notarized, stapled `.dmg` for direct download.

## 1. Build a DMG

```sh
scripts/package.sh
```

Without credentials this produces an **ad-hoc-signed** `build/Gitify-<version>.dmg` (fine for
local testing, not for distribution). To produce a distributable build, set:

```sh
# A one-time notarytool keychain profile:
xcrun notarytool store-credentials gitify-notary \
  --apple-id you@example.com --team-id TEAMID --password <app-specific-password>

export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="gitify-notary"
scripts/package.sh
```

The script then signs with the hardened runtime, notarizes via `notarytool`, and staples the
ticket. Spawning the user's `git` binary works under the hardened runtime with no extra
entitlement (git is Apple- or Developer-signed).

## 2. Auto-update

The app currently ships a lightweight in-app check (`UpdateChecker`) against the project's
GitHub releases: **Gitify ▸ Check for Updates…**, plus a quiet check on launch. Point
`UpdateChecker.repository` at the real `owner/repo`, and publish each release with a semver tag
(e.g. `v0.2.0`) and the DMG attached.

### Upgrading to Sparkle (recommended for production)

For silent, signed, delta auto-updates, integrate [Sparkle](https://sparkle-project.org):

1. Add the SPM dependency `https://github.com/sparkle-project/Sparkle` to `Package.swift` and
   link `Sparkle` into the `Gitify` target.
2. Generate an EdDSA key pair with Sparkle's `generate_keys`; keep the private key in the
   keychain, add the public key to `Resources/Info.plist` as `SUPublicEDKey`.
3. Add `SUFeedURL` (your hosted `appcast.xml`) and `SUEnableInstallerLauncherService` to
   `Info.plist`.
4. Embed `Sparkle.framework` (and its XPC services) into `Gitify.app/Contents/Frameworks` in
   `scripts/build-app.sh`, and code-sign each nested component before notarizing.
5. Replace `UpdateChecker` calls with `SPUStandardUpdaterController`.
6. Sign each release with `sign_update <dmg>` and publish the `appcast.xml`.

This step needs a Developer ID and a place to host the appcast, so it's done on a release
machine rather than in the headless build here.
