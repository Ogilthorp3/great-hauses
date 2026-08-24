#!/usr/bin/env bash
set -euo pipefail

PROJ="/Users/bert/Projects/great-hauses"
BRANDING="$PROJ/assets/branding"
SRC="$BRANDING/great_hauses_logo.jpg"

echo "=== Generating App Icons from $SRC ==="

# 1. Master PNG 1024x1024
sips -s format png "$SRC" --out "$BRANDING/app-icon-1024.png"
echo "Saved app-icon-1024.png"

# 2. Resized PNGs
for size in 512 256 128 64 32 16; do
    sips -z "$size" "$size" "$BRANDING/app-icon-1024.png" --out "$BRANDING/app-icon-$size.png" > /dev/null
    echo "Saved app-icon-$size.png"
done

# 3. macOS .icns via iconutil
ICONSET="$BRANDING/GreatHauses.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

cp "$BRANDING/app-icon-16.png"   "$ICONSET/icon_16x16.png"
cp "$BRANDING/app-icon-32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$BRANDING/app-icon-32.png"   "$ICONSET/icon_32x32.png"
cp "$BRANDING/app-icon-64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$BRANDING/app-icon-128.png"  "$ICONSET/icon_128x128.png"
cp "$BRANDING/app-icon-256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$BRANDING/app-icon-256.png"  "$ICONSET/icon_256x256.png"
cp "$BRANDING/app-icon-512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$BRANDING/app-icon-512.png"  "$ICONSET/icon_512x512.png"
cp "$BRANDING/app-icon-1024.png" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$BRANDING/GreatHauses.icns"
rm -rf "$ICONSET"
echo "Generated $BRANDING/GreatHauses.icns ($(wc -c < "$BRANDING/GreatHauses.icns") bytes)"

# 4. Windows .ico via ImageMagick
magick convert "$BRANDING/app-icon-16.png" "$BRANDING/app-icon-32.png" "$BRANDING/app-icon-64.png" "$BRANDING/app-icon-128.png" "$BRANDING/app-icon-256.png" "$BRANDING/GreatHauses.ico"
echo "Generated $BRANDING/GreatHauses.ico ($(wc -c < "$BRANDING/GreatHauses.ico") bytes)"

echo "=== All Icons Successfully Generated ==="
