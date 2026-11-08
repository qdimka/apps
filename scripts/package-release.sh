#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
tag="${1:-v$version}"
if [[ ! "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "Invalid release tag: expected vMAJOR.MINOR.PATCH." >&2
    exit 1
fi
if [[ "$tag" != "v$version" ]]; then
    echo "Release tag $tag does not match Info.plist version $version." >&2
    exit 1
fi
architecture="${APPS_EXPECTED_ARCH:-$(uname -m)}"
case "$architecture" in
    arm64|x86_64) ;;
    *) echo "Unsupported architecture: $architecture" >&2; exit 1 ;;
esac
if [[ "$(uname -m)" != "$architecture" ]]; then
    echo "Runner architecture does not match requested $architecture." >&2
    exit 1
fi
scripts/build-app.sh
app="dist/apps.app"
built_version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
test "$built_version" = "$version"
test "$(lipo -archs "$app/Contents/MacOS/apps")" = "$architecture"
test -x "$app/Contents/MacOS/apps"
plutil -lint "$app/Contents/Info.plist"
codesign --verify --deep --strict "$app"
archive="dist/apps-${tag}-macos-${architecture}.zip"
# ditto retains the bundle layout, resource metadata, and executable permissions.
# Create a fresh ZIP; never append files from an earlier version.
rm -f "$archive"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
/usr/bin/unzip -tq "$archive"
shasum -a 256 "$archive"
echo "Packaged: $archive"
