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

## 2. Auto-update (Sparkle)

The app uses [Sparkle](https://sparkle-project.org) for automatic updates. Sparkle checks the
appcast feed on launch and offers to download and install newer versions in-place.

### How it works

- `SUFeedURL` in `Info.plist` points to `appcast.xml` on the `main` branch (served via raw
  GitHub URL).
- Each release is signed with an EdDSA key pair. The public key is in `Info.plist`
  (`SUPublicEDKey`); the private key is stored as a GitHub Actions secret (`SPARKLE_PRIVATE_KEY`).
- The CI workflow (`release.yml`) signs each DMG with `sign_update`, appends an `<item>` to
  `appcast.xml`, and commits it back to `main`.

### EdDSA key management

The key pair is independent of Apple code signing. To regenerate:

```sh
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys              # creates key pair, prints public key
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle_private_key   # exports private key to file
cat sparkle_private_key                                         # copy this value for CI
rm sparkle_private_key                                          # don't leave the key on disk
```

- Store the **public key** (printed by `generate_keys`) in `Resources/Info.plist` as `SUPublicEDKey`.
- Store the **private key** (contents of the exported file) as the GitHub Actions secret `SPARKLE_PRIVATE_KEY`.

### Adding Apple code signing later

When a Developer ID is available, set `SIGN_IDENTITY` and `NOTARY_PROFILE` in CI to produce
signed and notarized DMGs. Sparkle works with both ad-hoc and Developer ID signed apps.
