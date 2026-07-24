#!/bin/bash
# Builds Claudar.app with just Command Line Tools (no Xcode needed)
# and installs it to ~/Applications.
#
# This build has NO WidgetKit widget — that needs Xcode and a signed App Group
# entitlement (see build-widget.sh). Menu bar and usage window work fully; the
# app simply has no widget to publish snapshots to.
set -euo pipefail
cd "$(dirname "$0")"

ARCH=$(uname -m)
APP="build/Claudar.app"

echo "Compiling…"
mkdir -p build
# Shared/ holds the model + formatting used by both the app and the widget.
swiftc -O -parse-as-library \
    -target "${ARCH}-apple-macos14.0" \
    Sources/*.swift Shared/*.swift \
    -o build/Claudar

echo "Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp build/Claudar "$APP/Contents/MacOS/Claudar"

# Icon: committed at Resources/AppIcon.icns, built from the masters in design/
# (see design/README.md to regenerate).
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "Signing (ad-hoc)…"
codesign --force --sign - "$APP"

echo "Installing to ~/Applications…"
mkdir -p ~/Applications
rm -rf ~/Applications/"Claudar.app"
cp -R "$APP" ~/Applications/

echo "Done: ~/Applications/Claudar.app"

# Package for distribution when asked: ./build.sh --package
if [ "${1:-}" = "--package" ]; then
    ZIP="build/Claudar-menubar.zip"
    rm -f "$ZIP"
    # ditto preserves the bundle's signature and metadata; `zip` does not.
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
    echo "Packaged: $ZIP"
fi
