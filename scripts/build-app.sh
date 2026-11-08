#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
if [[ "$configuration" != release && "$configuration" != debug ]]; then
    echo "Usage: scripts/build-app.sh [release|debug]" >&2
    exit 2
fi
scripts/swift-local.sh build -c "$configuration" --product apps
binary_dir="$(scripts/swift-local.sh build -c "$configuration" --show-bin-path)"
app="$PWD/dist/apps.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build/icon
binary_tmp="$(mktemp "$app/Contents/MacOS/.apps.XXXXXX")"
trap 'rm -f "$binary_tmp"' EXIT
cp "$binary_dir/apps" "$binary_tmp"
chmod 755 "$binary_tmp"
mv -f "$binary_tmp" "$app/Contents/MacOS/apps"
cp Resources/Info.plist "$app/Contents/Info.plist"

icon_flags=(-module-cache-path "$PWD/.build/module-cache")
if [[ -f .build/toolchain/overlay.json ]]; then
    icon_flags+=(-vfsoverlay "$PWD/.build/toolchain/overlay.json")
fi
swift "${icon_flags[@]}" scripts/make-icon.swift "$PWD/.build/icon/master.png"
iconset="$PWD/.build/icon/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" .build/icon/master.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" .build/icon/master.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
plutil -lint "$app/Contents/Info.plist"
if command -v codesign >/dev/null; then
    codesign --force --sign - "$app"
    codesign --verify --deep --strict "$app"
fi
echo "Built: $app"
