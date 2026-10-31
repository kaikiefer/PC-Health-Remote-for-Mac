#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
RELEASE_ARCH="${ARCH:-universal}"
if [[ $# -eq 0 ]]; then
    ARCH="$RELEASE_ARCH" ./scripts/build.sh
elif [[ $# -ne 1 || "$1" != --skip-build ]]; then
    printf 'Usage: scripts/release.sh [--skip-build]\n' >&2; exit 1
fi
APP="$PWD/build/PC Health Remote.app"
codesign --verify --deep --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
SOURCE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
[[ "$VERSION" == "$SOURCE_VERSION" ]] || { printf 'Built version differs from Info.plist. Rebuild first.\n' >&2; exit 1; }
if [[ -n "${RELEASE_TAG:-}" && "$RELEASE_TAG" != "v$VERSION" ]]; then
    printf 'Tag %s does not match app version v%s. Update Info.plist before tagging.\n' "$RELEASE_TAG" "$VERSION" >&2
    exit 1
fi
case "$RELEASE_ARCH" in
    universal) EXPECTED_ARCHES="arm64 x86_64" ;;
    arm64|x86_64) EXPECTED_ARCHES="$RELEASE_ARCH" ;;
    *) printf 'Unsupported architecture.\n' >&2; exit 1 ;;
esac
for EXPECTED_ARCH in $EXPECTED_ARCHES; do
    xcrun lipo "$APP/Contents/MacOS/PCHealthRemote" -verify_arch "$EXPECTED_ARCH"
done
DIST="$PWD/build/releases"
mkdir -p "$DIST"
ARCHIVE_NAME="PC-Health-Remote-v$VERSION-$RELEASE_ARCH.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$ARCHIVE_NAME"
(
    cd "$DIST"
    shasum -a 256 "$ARCHIVE_NAME" > "PC-Health-Remote-v$VERSION-$RELEASE_ARCH.sha256"
)
cat > "$DIST/RELEASE_NOTES.md" <<EOF
# PC Health Remote for Mac v$VERSION

Native macOS companion for the PC Health Remote Flipper Zero app.

- Cyan/orange desktop HUD, Pulse Link identity, and live CPU/GPU traces.
- CPU/GPU temperatures, load, RAM, shared GPU memory, disk, battery, uptime,
  CPU clock, and fan readings where supported.
- USB and Bluetooth LE transport, menu bar operation, and optional Open at login.
- Saved Celsius/Fahrenheit dashboard preference; Flipper data stays Celsius.

Requires macOS 13 or later and the separately installed PC Health Remote app
on Flipper. Close qFlipper before using USB. Apple silicon hardware readings
were validated on M3, including USB and an already-paired BLE reconnect;
other chips/Intel sensors and first-time BLE pairing need further manual
validation. Fanless Macs have no RPM reading. VRAM means GPU-resident
shared memory on Apple silicon.

This is a full-featured direct-distribution build, not a Mac App Store build.
Default builds are locally ad-hoc signed and are not Apple-notarized.
Gatekeeper may block a downloaded app. The source is provided so users can
build locally; Apple Developer ID signing/notarization is a separate release step.

Download $ARCHIVE_NAME, extract it, and move PC Health Remote.app to Applications.
The adjacent .sha256 file records the archive checksum.
See README.md, PRIVACY.md and NOTICE.md in the source repository.
EOF
printf 'Release files prepared in %s\n' "$DIST"
