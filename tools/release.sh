#!/bin/sh
# Builds a release DMG of RawBoy Viewer: build/release/RawBoy-Viewer-<version>.dmg
#
#   tools/release.sh <version> [build number]
#
# Signing (docs/releasing.md walks through it):
#   DEVELOPER_ID    "Developer ID Application: Your Name (TEAMID)" (paid Apple Developer Program): signs for others
#   NOTARY_PROFILE  a notarytool keychain profile (paid program too): notarizes, so others can open it normally
# Without DEVELOPER_ID the app is signed as Config/ says: Config/Signing.local.xcconfig's certificate (a free
# Personal Team's "Apple Development" works) or ad hoc. Either way others open it with right-click › Open.
set -e
cd "$(dirname "$0")/.."
VERSION=${1:?usage: tools/release.sh <version> [build number]}
BUILD=${2:-$(git rev-list --count HEAD)}
OUT=build/release
APP_NAME="RawBoy Viewer"
DMG="$OUT/RawBoy-Viewer-$VERSION.dmg"
rm -rf "$OUT" && mkdir -p "$OUT"

xcodegen -q

if [ -n "$DEVELOPER_ID" ]; then
    SIGN="CODE_SIGN_IDENTITY=$DEVELOPER_ID CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS=--timestamp"
    echo "Signing with $DEVELOPER_ID"
else
    SIGN=""
    echo "No DEVELOPER_ID: signing as Config/ says (not notarizable)"
fi

# shellcheck disable=SC2086
xcodebuild -project RawBoyViewer.xcodeproj -scheme RawBoyViewer -configuration Release \
    -archivePath "$OUT/RawBoyViewer.xcarchive" -destination 'generic/platform=macOS' \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" $SIGN archive | grep -E "error:|ARCHIVE" || true
APP="$OUT/RawBoyViewer.xcarchive/Products/Applications/$APP_NAME.app"
[ -d "$APP" ] || { echo "The archive has no app: see the build log above." >&2; exit 1; }
codesign --verify --deep --strict "$APP"
TEAM=$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')
echo "Built $APP_NAME $VERSION ($BUILD), signed $([ "$TEAM" = "not set" ] || [ -z "$TEAM" ] && echo "ad hoc" || echo "by team $TEAM")"

# The disk image: the app and a link to /Applications to drag it onto.
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "$DEVELOPER_ID" ] && [ -n "$NOTARY_PROFILE" ]; then
    codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
    echo "Notarizing (takes a few minutes)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
else
    echo "Not notarized: set DEVELOPER_ID and NOTARY_PROFILE for a DMG others can open."
fi
shasum -a 256 "$DMG"
