#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from a source PNG.
#
# The source artwork is a dark rounded-square ("squircle") on a solid light
# background. This script flood-fills that background to transparent, crops to
# the artwork so it fills the icon tile, pads to a square canvas to preserve the
# shape, then emits a full .iconset and compiles it to AppIcon.icns.
#
# Usage: scripts/make-appicon.sh /path/to/source.png
set -euo pipefail

SRC="${1:?usage: make-appicon.sh <source.png>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
MASTER="${WORK}/master.png"
ICONSET="${WORK}/Gitify.iconset"
mkdir -p "${ICONSET}"

echo "==> Removing background and cropping artwork"
python3 - "${SRC}" "${MASTER}" <<'PY'
import sys
from PIL import Image, ImageDraw

src = Image.open(sys.argv[1]).convert("RGBA")
W, H = src.size

# Flood-fill the solid background (seeded from the four corners) to a sentinel
# colour, treating near-background greys/shadow as background via the threshold.
rgb = src.convert("RGB")
SENTINEL = (255, 0, 255)
for seed in [(0, 0), (W - 1, 0), (0, H - 1), (W - 1, H - 1)]:
    ImageDraw.floodfill(rgb, seed, SENTINEL, thresh=70)

# Apply transparency wherever the fill reached.
out = src.copy()
sp, op = rgb.load(), out.load()
for y in range(H):
    for x in range(W):
        if sp[x, y] == SENTINEL:
            op[x, y] = (0, 0, 0, 0)

# Crop tightly to the remaining (opaque) artwork so it fills the tile.
bbox = out.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
art = out.crop(bbox)
aw, ah = art.size

# Pad to a centred square canvas to preserve the artwork's aspect ratio.
side = max(aw, ah)
canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
canvas.paste(art, ((side - aw) // 2, (side - ah) // 2), art)
canvas = canvas.resize((1024, 1024), Image.LANCZOS)
canvas.save(sys.argv[2])
print(f"   artwork {aw}x{ah} -> 1024x1024 square master")
PY

echo "==> Generating iconset"
gen() { sips -z "$1" "$1" "${MASTER}" --out "${ICONSET}/$2" >/dev/null; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
gen 1024 icon_512x512@2x.png

echo "==> Compiling AppIcon.icns"
iconutil -c icns "${ICONSET}" -o "${ROOT}/Resources/AppIcon.icns"
cp "${ROOT}/Resources/AppIcon.icns" "${ROOT}/Sources/Gitify/Resources/AppIcon.icns"

echo "==> Wrote Resources/AppIcon.icns and Sources/Gitify/Resources/AppIcon.icns"
