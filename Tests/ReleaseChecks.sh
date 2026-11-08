#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/scripts" "$fixture/Resources"
cp scripts/package-release.sh "$fixture/scripts/"
cp Resources/Info.plist "$fixture/Resources/"
cat > "$fixture/scripts/build-app.sh" <<'STUB'
#!/bin/bash
touch "$(dirname "$0")/unexpected-build"
exit 98
STUB
chmod +x "$fixture/scripts/build-app.sh"
reject() {
    local tag="$1" message="$2"
    if "$fixture/scripts/package-release.sh" "$tag" > "$fixture/result" 2>&1; then
        echo "FAIL: accepted invalid tag $tag" >&2; exit 1
    fi
    if ! /usr/bin/grep -q "$message" "$fixture/result"; then
        cat "$fixture/result" >&2; exit 1
    fi
    test ! -e "$fixture/scripts/unexpected-build"
}
reject 'v1.2.3; echo unexpected' 'Invalid release tag'
reject 'v01.2.3' 'Invalid release tag'
reject 'v999.0.0' 'does not match'
APPS_EXPECTED_ARCH=invalid reject '' 'Unsupported architecture'
echo '4 release preflight checks passed; no build invoked.'
