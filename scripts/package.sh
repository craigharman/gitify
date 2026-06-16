#!/usr/bin/env bash
# Builds a distributable Gitify.dmg. Signing and notarization are applied only when the
# relevant credentials are provided via environment variables, so this runs end-to-end
# locally (unsigned) and produces a notarized, stapled DMG in CI / on a release machine.
#
# Optional environment variables:
#   SIGN_IDENTITY   Developer ID Application identity, e.g.
#                   "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE  notarytool keychain profile created with:
#                   xcrun notarytool store-credentials NOTARY_PROFILE \
#                     --apple-id you@example.com --team-id TEAMID --password <app-specific>
#
# Usage: scripts/package.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${ROOT}/build/Gitify.app"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ROOT}/Resources/Info.plist")"
DMG="${ROOT}/build/Gitify-${VERSION}.dmg"

echo "==> Building release app bundle"
"${ROOT}/scripts/build-app.sh" release

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "==> Code signing with Developer ID (hardened runtime)"
  codesign --force --deep --options runtime --timestamp \
    --sign "${SIGN_IDENTITY}" "${APP}"
  codesign --verify --strict --verbose=2 "${APP}"
else
  echo "==> SIGN_IDENTITY not set - leaving the ad-hoc signature (not distributable)"
fi

echo "==> Building DMG"
rm -f "${DMG}"
STAGE="$(mktemp -d)"
cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"
hdiutil create -volname "Gitify" -srcfolder "${STAGE}" -ov -format UDZO "${DMG}" >/dev/null
rm -rf "${STAGE}"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "${SIGN_IDENTITY}" "${DMG}"
fi

if [[ -n "${SIGN_IDENTITY:-}" && -n "${NOTARY_PROFILE:-}" ]]; then
  echo "==> Submitting to Apple notary service (this can take a few minutes)"
  xcrun notarytool submit "${DMG}" --keychain-profile "${NOTARY_PROFILE}" --wait
  echo "==> Stapling notarization ticket"
  xcrun stapler staple "${DMG}"
  xcrun stapler validate "${DMG}"
else
  echo "==> Skipping notarization (needs SIGN_IDENTITY + NOTARY_PROFILE)"
fi

echo "==> Built ${DMG}"
