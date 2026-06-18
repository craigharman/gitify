#!/usr/bin/env bash
# Assembles Gitify.app from the SwiftPM executable. Because the project builds without
# Xcode, we construct the .app bundle by hand and ad-hoc sign it so it can launch locally.
#
# Usage: scripts/build-app.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${ROOT}/build/Gitify.app"

echo "==> Building Gitify (${CONFIG})"
swift build --product Gitify -c "${CONFIG}"

BIN="$(swift build --product Gitify -c "${CONFIG}" --show-bin-path)/Gitify"

echo "==> Assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/Gitify"

# Copy the SwiftPM-generated resource bundle so Bundle.module works at runtime.
BUNDLE_DIR="$(dirname "${BIN}")"
if [[ -d "${BUNDLE_DIR}/Gitify_Gitify.bundle" ]]; then
  cp -R "${BUNDLE_DIR}/Gitify_Gitify.bundle" "${APP}/Contents/Resources/"
fi
cp "${ROOT}/Resources/Info.plist" "${APP}/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP}/Contents/Info.plist"
fi
cp "${ROOT}/Resources/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "${APP}" >/dev/null 2>&1 || \
  echo "    (codesign skipped - app will still run locally)"

echo "==> Built ${APP}"
echo "    Launch with:  open \"${APP}\""
