#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$PWD/build/ModuleCache"
APP="$PWD/build/PC Health Remote.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SDK="$(xcrun --show-sdk-path)"
BUILD_ARCH="${ARCH:-$(uname -m)}"
case "$BUILD_ARCH" in
    universal) ARCHITECTURES=(arm64 x86_64) ;;
    arm64|x86_64) ARCHITECTURES=("$BUILD_ARCH") ;;
    *) printf 'Unsupported architecture: %s\n' "$BUILD_ARCH" >&2; exit 1 ;;
esac
BINARIES=()
for TARGET_ARCH in "${ARCHITECTURES[@]}"; do
    xcrun clang -O2 -Wall -Wextra -isysroot "$SDK" -target "$TARGET_ARCH-apple-macosx13.0" \
        -c Sources/Hardware/Hardware.c -o "build/Hardware-$TARGET_ARCH.o"
    xcrun swiftc -parse-as-library -O -whole-module-optimization -sdk "$SDK" -target "$TARGET_ARCH-apple-macosx13.0" \
        -import-objc-header Sources/Hardware/Hardware.h Sources/PCHealthRemote/*.swift "build/Hardware-$TARGET_ARCH.o" \
        -o "build/PCHealthRemote-$TARGET_ARCH" \
        -framework SwiftUI -framework AppKit -framework CoreBluetooth -framework IOKit -framework ServiceManagement
    BINARIES+=("build/PCHealthRemote-$TARGET_ARCH")
done
xcrun lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/PCHealthRemote"
cp Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp NOTICE.md "$APP/Contents/Resources/NOTICE.md"
cp PRIVACY.md "$APP/Contents/Resources/PRIVACY.md"
cp ThirdParty/macmon-LICENSE "$APP/Contents/Resources/macmon-LICENSE"
if [[ ! -f Assets/Brand/logo-mark.png || ! -f Assets/Assets.xcassets/AppIcon.appiconset/Contents.json || scripts/MakeIcon.swift -nt Assets/Brand/logo-mark.png ]]; then
    ./scripts/prepare-assets.sh
fi
cp Assets/Brand/logo-mark.png "$APP/Contents/Resources/LogoMark.png"
if [[ ! -f "$APP/Contents/Resources/AppIcon.icns" || scripts/MakeIcon.swift -nt "$APP/Contents/Resources/AppIcon.icns" ]]; then
    if [[ ! -f build/AppIcon.iconset/icon_512x512@2x.png ]]; then
        ./scripts/prepare-assets.sh
    fi
    iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
fi
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
printf 'Built %s (%s)\n' "$APP" "$BUILD_ARCH"
