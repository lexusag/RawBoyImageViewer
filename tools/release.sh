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
#
# CI (.github/workflows/release.yml) sets SPARKLE_KEY_FILE (the Sparkle private key, instead of the keychain) and
# SKIP_APPCAST=1 (when it has no key: the DMG is built but the feed is left alone).
#
# Updates: the DMG is signed with Sparkle's key (in the login keychain) and added to appcast.xml. With PUBLISH=1 the
# script also creates the GitHub release v<version> (PRERELEASE=1: marked pre-release) with docs/releases/v<version>.md
# as its notes, then commits and pushes appcast.xml, which the app's SUFeedURL reads.
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
    -clonedSourcePackagesDirPath build/SourcePackages \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" $SIGN archive | grep -E "error:|ARCHIVE" || true
APP="$OUT/RawBoyViewer.xcarchive/Products/Applications/$APP_NAME.app"
[ -d "$APP" ] || { echo "The archive has no app: see the build log above." >&2; exit 1; }

# Sparkle.framework ships signed with its own developer's Team ID. dyld refuses to load a framework whose Team ID
# differs from the app's ("mapping process and mapped file have different Team IDs"), which crashed the ad hoc DMG at
# launch. So when the app is ad hoc signed, sign Sparkle's nested code, the framework and then the app again with the
# same ad hoc identity, inside-out. (Developer ID builds are re-signed by Xcode with the app's own identity.)
team_of() { codesign -dv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p'; }
if [ "$(team_of "$APP")" = "not set" ] || [ -z "$(team_of "$APP")" ]; then
    echo "Ad hoc: re-signing embedded frameworks with the app's identity"
    for FW in "$APP"/Contents/Frameworks/*.framework; do
        [ -d "$FW" ] || continue
        find "$FW" -depth \( -name "*.xpc" -o -name "*.app" -o -perm -u+x -type f -path "*/Versions/*/Autoupdate" \) \
            -exec codesign --force --sign - --preserve-metadata=identifier,entitlements {} \;
        codesign --force --sign - --preserve-metadata=identifier,entitlements "$FW"
    done
    codesign --force --sign - --preserve-metadata=identifier,entitlements "$APP"
fi
# The hardened runtime turns on library validation, and macOS 27 rejects an ad hoc framework there even when it is
# signed with the same ad hoc identity as the app (the 0.0.2 DMG still crashed). An ad hoc app has no Team ID to
# match anyway, so it must not carry the runtime flag.
if [ "$(team_of "$APP")" = "not set" ] || [ -z "$(team_of "$APP")" ]; then
    for C in "$APP" "$APP"/Contents/Frameworks/*.framework; do
        if codesign -dv "$C" 2>&1 | grep -q 'flags=.*runtime'; then
            echo "$C is ad hoc but has the hardened runtime: it will not load Sparkle." >&2; exit 1
        fi
    done
fi
codesign --verify --deep --strict "$APP"
# Every Mach-O in the app must carry the app's Team ID (empty when ad hoc), or it won't launch.
APP_TEAM=$(team_of "$APP")
for F in "$APP"/Contents/Frameworks/*.framework; do
    [ -d "$F" ] || continue
    FT=$(team_of "$F")
    [ "$FT" = "$APP_TEAM" ] || { echo "Team ID mismatch: $F is '$FT', the app is '$APP_TEAM'" >&2; exit 1; }
done
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

if [ -n "$SKIP_APPCAST" ]; then
    echo "SKIP_APPCAST set: appcast.xml left alone."
else
# Sparkle: the update feed. generate_appcast signs the DMG with the key in the keychain and adds it to the feed
# (entries for earlier versions stay).
SPARKLE=build/SourcePackages/artifacts/sparkle/Sparkle/bin
REPO=lexusag/RawBoyImageViewer
FEED="$OUT/appcast"
mkdir -p "$FEED"
cp "$DMG" "$FEED/"
[ -f appcast.xml ] && cp appcast.xml "$FEED/appcast.xml"
NOTES="docs/releases/v$VERSION.md"
[ -f "$NOTES" ] && cp "$NOTES" "$FEED/RawBoy-Viewer-$VERSION.md"
"$SPARKLE/generate_appcast" ${SPARKLE_KEY_FILE:+--ed-key-file "$SPARKLE_KEY_FILE"} --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
    --embed-release-notes --link "https://github.com/$REPO" "$FEED" >/dev/null
cp "$FEED/appcast.xml" appcast.xml
echo "appcast.xml now lists $(grep -c '<item>' appcast.xml) release(s)"
fi

if [ -n "$PUBLISH" ]; then
    [ -f "$NOTES" ] || { echo "Write $NOTES first: it is the release's notes." >&2; exit 1; }
    git tag "v$VERSION"
    git push origin "v$VERSION"
    gh release create "v$VERSION" "$DMG" --repo "$REPO" --title "RawBoy Viewer $VERSION" --notes-file "$NOTES" \
        ${PRERELEASE:+--prerelease}
    git add appcast.xml
    git commit -m "Update feed: $VERSION"
    git push
    echo "Published v$VERSION: https://github.com/$REPO/releases/tag/v$VERSION"
else
    echo "Not published (PUBLISH=1 publishes): appcast.xml is updated here only."
fi
