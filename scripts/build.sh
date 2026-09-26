#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

xcrun swift build -c release --product SwiftSnips
binary_dir="$(xcrun swift build -c release --show-bin-path)"
bundle="dist/SwiftSnips.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_dir/SwiftSnips" "$bundle/Contents/MacOS/SwiftSnips"
cp scripts/Info.plist "$bundle/Contents/Info.plist"

if [ ! -f dist/AppIcon.icns ]; then
  mkdir -p dist/AppIcon.iconset
  xcrun swift scripts/create-icon.swift dist/icon-1024.png
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" dist/icon-1024.png --out "dist/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" dist/icon-1024.png --out "dist/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns dist/AppIcon.iconset -o dist/AppIcon.icns
fi
cp dist/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"

# Ad hoc signing is for local source builds. Set an identity to retain a stable
# Accessibility identity across rebuilds.
codesign --force --sign "${SWIFTSNIPS_SIGN_IDENTITY:--}" --timestamp=none --options runtime "$bundle"
codesign --verify --strict "$bundle"
echo "Built and verified: $PWD/$bundle"
