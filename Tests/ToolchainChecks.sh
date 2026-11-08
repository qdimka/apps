#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/scripts" "$fixture/bin" "$fixture/developer"
cp scripts/swift-local.sh "$fixture/scripts/"
cat > "$fixture/bin/xcode-select" <<'STUB'
#!/bin/bash
printf '%s\n' "$APPS_TEST_DEVELOPER"
STUB
cat > "$fixture/bin/swift" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$APPS_WRAPPER_LOG"
STUB
chmod +x "$fixture/bin/"*
run_wrapper() {
    PATH="$fixture/bin:/usr/bin:/bin" APPS_TEST_DEVELOPER="$fixture/developer" APPS_WRAPPER_LOG="$fixture/arguments" \
        /bin/bash "$fixture/scripts/swift-local.sh" build --product apps
    /usr/bin/grep -qx -- 'build' "$fixture/arguments"
    /usr/bin/grep -qx -- '--product' "$fixture/arguments"
    /usr/bin/grep -qx -- 'apps' "$fixture/arguments"
}
run_wrapper
if /usr/bin/grep -qx -- '-vfsoverlay' "$fixture/arguments"; then
    echo 'Clean toolchain unexpectedly received an overlay.' >&2; exit 1
fi
mkdir -p "$fixture/developer/usr/include/swift"
touch "$fixture/developer/usr/include/swift/module.modulemap" "$fixture/developer/usr/include/swift/bridging.modulemap"
run_wrapper
/usr/bin/grep -qx -- '-vfsoverlay' "$fixture/arguments"
test -f "$fixture/.build/toolchain/overlay.json"
echo '2 toolchain-wrapper checks passed with system Bash.'
