#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
# Some Command Line Tools installations retain Swift 5 private interfaces
# alongside Swift 6 libraries. Prefer the matching public interfaces locally.
manifest_api="$(xcode-select -p)/usr/lib/swift/pm/ManifestAPI"
if [[ -f "$manifest_api/PackageDescription.swiftmodule/arm64-apple-macos.private.swiftinterface" ]] &&
   /usr/bin/grep -q 'Apple Swift version 5.10' "$manifest_api/PackageDescription.swiftmodule/arm64-apple-macos.private.swiftinterface" &&
   /usr/bin/grep -q 'Apple Swift version 6' "$manifest_api/PackageDescription.swiftmodule/arm64-apple-macos.swiftinterface"; then
    local_api="$PWD/.build/swiftpm-libs/ManifestAPI"
    mkdir -p "$local_api/PackageDescription.swiftmodule"
    cp "$manifest_api/PackageDescription.swiftmodule/"*.swiftinterface "$local_api/PackageDescription.swiftmodule/"
    rm -f "$local_api/PackageDescription.swiftmodule/"*.private.swiftinterface
    ln -sf "$manifest_api/libPackageDescription.dylib" "$local_api/libPackageDescription.dylib"
    export SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build/swiftpm-libs"
fi
overlay_flags=()
if [[ -f "$(xcode-select -p)/usr/include/swift/module.modulemap" ]] &&
   [[ -f "$(xcode-select -p)/usr/include/swift/bridging.modulemap" ]]; then
    mkdir -p .build/toolchain
    printf '\n' > .build/toolchain/empty.modulemap
    /usr/bin/python3 - "$PWD" "$(xcode-select -p)" <<'PY'
import json, pathlib, sys
root, developer = sys.argv[1:]
overlay = {'version': 0, 'roots': [{'type': 'file', 'name': developer + '/usr/include/swift/module.modulemap', 'external-contents': root + '/.build/toolchain/empty.modulemap'}]}
pathlib.Path(root + '/.build/toolchain/overlay.json').write_text(json.dumps(overlay))
PY
    overlay_flags=(-Xswiftc -vfsoverlay -Xswiftc "$PWD/.build/toolchain/overlay.json")
fi
command="$1"
shift
exec swift "$command" --disable-sandbox --cache-path "$PWD/.build/cache" "${overlay_flags[@]}" "$@"
