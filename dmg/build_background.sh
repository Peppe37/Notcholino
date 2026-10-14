#!/bin/sh
# Renders background.html into background.tiff (1x + 2x for Retina) using headless Chrome.
# Usage: dmg/build_background.sh   (needs Google Chrome)
set -e
cd "$(dirname "$0")"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
TMP="$(mktemp -d)"
for s in 1 2; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=$s \
    --window-size=660,420 --default-background-color=00000000 \
    --screenshot="$TMP/bg$s.png" "file://$PWD/background.html" >/dev/null 2>&1
done
# Name the 2x image so the pair is recognised as a Retina set
mv "$TMP/bg2.png" "$TMP/bg@2x.png"
tiffutil -cathidpicheck "$TMP/bg1.png" "$TMP/bg@2x.png" -out background.tiff
sips -g pixelWidth -g pixelHeight "$TMP/bg1.png" "$TMP/bg@2x.png" | grep -E "pixel"
rm -rf "$TMP"
