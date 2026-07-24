#!/bin/bash
# Builds Claudar.app *with* the WidgetKit widget extension.
# Requires Xcode and an Apple ID signed in (Xcode ▸ Settings ▸ Accounts) —
# a free Apple ID is enough. The App Group entitlement that lets the app share
# data with the widget cannot be ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")"

# 1. Find a development team.
# NB: `|| true` on each — these exit non-zero when nothing is signed in, and
# `set -e` would otherwise abort the script before the guidance below prints.
#
# Order matters. The id in a certificate's name ("Apple Development: you
# (XXXXXXXXXX)") is the CERTIFICATE id, not the team id — signing with it fails.
# The authoritative source is the team Xcode wrote into the project, or a
# provisioning profile, so check those first.
if [ -z "${DEVELOPMENT_TEAM:-}" ] && [ -f Claudar.xcodeproj/project.pbxproj ]; then
    DEVELOPMENT_TEAM=$(sed -n 's/.*DEVELOPMENT_TEAM = \([A-Z0-9]\{10\}\);.*/\1/p' \
        Claudar.xcodeproj/project.pbxproj | head -1 || true)
fi
if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
    # Team id lives in the provisioning profile Xcode generated.
    DEVELOPMENT_TEAM=$(find ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles \
        -name "*.provisionprofile" -newermt "-90 days" 2>/dev/null \
        | head -1 | xargs -I{} security cms -D -i {} 2>/dev/null \
        | plutil -extract TeamIdentifier.0 raw - 2>/dev/null || true)
fi
if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
    cat >&2 <<'MSG'
No development team found.

Open Xcode ▸ Settings (⌘,) ▸ Accounts ▸ "+" ▸ Apple ID and sign in.
A free Apple ID works — no paid developer account needed. Xcode then creates a
"Personal Team" and a development certificate, and this script will find it.

Then re-run: ./build-widget.sh
MSG
    exit 1
fi
echo "Using development team: $DEVELOPMENT_TEAM"

# 2. Regenerate the project with that team baked in.
export DEVELOPMENT_TEAM
xcodegen generate

# 3. Build.
echo "Building…"
xcodebuild -project Claudar.xcodeproj \
    -scheme Claudar \
    -configuration Release \
    -derivedDataPath build/dd \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    build | tail -20

APP="build/dd/Build/Products/Release/Claudar.app"
[ -d "$APP" ] || { echo "Build produced no app at $APP" >&2; exit 1; }

# 4. Install. The widget is registered from the installed copy, so it has to
#    live somewhere stable — /Applications is where macOS looks first.
echo "Installing to /Applications…"
pkill -x Claudar 2>/dev/null || true
rm -rf "/Applications/Claudar.app"
cp -R "$APP" "/Applications/Claudar.app"

# 5. Nudge the widget system to notice the new extension.
pluginkit -a "/Applications/Claudar.app/Contents/PlugIns/ClaudarWidget.appex" 2>/dev/null || true
killall chronod 2>/dev/null || true

open "/Applications/Claudar.app"
echo
echo "Done. Add the widget: right-click the desktop ▸ Edit Widgets ▸ search “Claudar”."
