#!/usr/bin/env bash
# Rebuild the social and web image kit served on /brand: profile pictures, the
# link-preview image and text-free post canvases in the five Nordic colors.
#
# Needs ImageMagick (`magick`) and `zip`. Run from the repository root:
#   etc/scripts/brand/make_social_kit.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOGOS="$ROOT/priv/static/images/brand/logos"
OUT="$ROOT/priv/static/images/brand/kit"
NAVY="#00205B"

mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Tight crops (no transparent margin) of the two seals we place.
magick "$LOGOS/ysc-logo-seal-white-center.png" -trim +repage "$WORK/seal-light.png"
magick "$LOGOS/ysc-logo-seal-white-ring.png" -trim +repage "$WORK/seal-dark.png"

# Profile pictures: 1080 square, seal at 76% so round crops stay clear of the edge.
magick -size 1080x1080 xc:white \( "$WORK/seal-light.png" -resize 820x820 \) \
  -gravity center -composite "$OUT/ysc-profile-seal-white.png"
magick -size 1080x1080 "xc:$NAVY" \( "$WORK/seal-dark.png" -resize 820x820 \) \
  -gravity center -composite "$OUT/ysc-profile-seal-navy.png"

# Link preview (Open Graph): 1200x630, navy, seal centered.
magick -size 1200x630 "xc:$NAVY" \( "$WORK/seal-dark.png" -resize x430 \) \
  -gravity center -composite "$OUT/ysc-link-preview-1200x630.png"

# Text-free post canvases: country color field, seal bottom-left in the safe zone.
canvas() {
  local country="$1" color="$2" width="$3" height="$4" kind="$5"
  local logo=$((width * 20 / 100))
  local margin=$((width * 5 / 100))
  magick -size "${width}x${height}" "xc:$color" \
    \( "$WORK/seal-light.png" -resize "${logo}x${logo}" \) \
    -gravity southwest -geometry "+${margin}+${margin}" -composite \
    "$OUT/ysc-canvas-${kind}-${width}x${height}-${country}.png"
}

while read -r country color; do
  canvas "$country" "$color" 1080 1080 square
  canvas "$country" "$color" 1200 630 landscape
  canvas "$country" "$color" 1080 1920 story
done <<'EOF'
denmark #C8102E
finland #002F6C
iceland #02529C
norway #00205B
sweden #FECB00
EOF

rm -f "$OUT/ysc-social-kit.zip"
(cd "$OUT" && zip -q ysc-social-kit.zip ./*.png)
echo "Wrote $(find "$OUT" -name '*.png' | wc -l | tr -d ' ') PNGs and ysc-social-kit.zip to $OUT"
