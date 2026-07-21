#!/bin/bash
# Builds Claude Usage.app with just Command Line Tools (no Xcode needed)
# and installs it to ~/Applications.
#
# This build has NO WidgetKit widget — that needs Xcode and a signed App Group
# entitlement (see build-widget.sh). Menu bar and usage window work fully; the
# app simply has no widget to publish snapshots to.
set -euo pipefail
cd "$(dirname "$0")"

ARCH=$(uname -m)
APP="build/Claude Usage.app"

echo "Compiling…"
mkdir -p build
# Shared/ holds the model + formatting used by both the app and the widget.
swiftc -O -parse-as-library \
    -target "${ARCH}-apple-macos14.0" \
    Sources/*.swift Shared/*.swift \
    -o build/ClaudeUsage

echo "Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp build/ClaudeUsage "$APP/Contents/MacOS/ClaudeUsage"

# Icon: regenerate if the master or icns is missing.
if [ ! -f build/AppIcon.icns ]; then
    swift tools/gen_icon.swift build/icon_1024.png
    rm -rf build/AppIcon.iconset && mkdir build/AppIcon.iconset
    for s in 16 32 128 256 512; do
        sips -z $s $s build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
        d=$((s*2))
        sips -z $d $d build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "Signing (ad-hoc)…"
codesign --force --sign - "$APP"

echo "Installing to ~/Applications…"
mkdir -p ~/Applications
rm -rf ~/Applications/"Claude Usage.app"
cp -R "$APP" ~/Applications/

echo "Done: ~/Applications/Claude Usage.app"

# Package for distribution when asked: ./build.sh --package
if [ "${1:-}" = "--package" ]; then
    ZIP="build/ClaudeUsage-menubar.zip"
    rm -f "$ZIP"
    # ditto preserves the bundle's signature and metadata; `zip` does not.
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
    echo "Packaged: $ZIP"
fi
