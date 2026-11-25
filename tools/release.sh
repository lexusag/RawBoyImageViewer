#!/bin/sh
# Builds a release DMG of RawBoy Viewer: build/release/RawBoy-Viewer-<version>.dmg
#
#   tools/release.sh <version> [build number]
#
# Signing (docs/releasing.md walks through it):
#   DEVELOPER_ID            "Developer ID Application: Your Name (TEAMID)" (paid Apple Developer Program): signs for others
#   KEYCHAIN                optional keychain path holding DEVELOPER_ID (used by CI)
#   APPLE_NOTARY_KEY_FILE   path to App Store Connect API AuthKey_<KEYID>.p8 (with APPLE_NOTARY_KEY_ID, APPLE_NOTARY_ISSUER_ID)
#   NOTARY_PROFILE          alternative to the API key: a notarytool keychain profile stored on a local Mac
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
    echo "Will sign with $DEVELOPER_ID (Hardened Runtime + secure timestamp)"
else
    echo "No DEVELOPER_ID: signing as Config/ says (not notarizable)"
fi

xcodebuild -project RawBoyViewer.xcodeproj -scheme RawBoyViewer -configuration Release \
    -archivePath "$OUT/RawBoyViewer.xcarchive" -destination 'generic/platform=macOS' \
    -clonedSourcePackagesDirPath build/SourcePackages \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" archive | grep -E "error:|ARCHIVE" || true
APP="$OUT/RawBoyViewer.xcarchive/Products/Applications/$APP_NAME.app"
[ -d "$APP" ] || { echo "The archive has no app: see the build log above." >&2; exit 1; }

# Sparkle.framework ships signed with its own developer's Team ID. dyld refuses to load a framework whose Team ID
# differs from the app's ("mapping process and mapped file have different Team IDs").
# - With DEVELOPER_ID: sign Sparkle's nested binaries, every embedded framework/dylib, and the app itself inside-out
#   with Hardened Runtime (--options runtime) and a secure timestamp (--timestamp) so Apple notarization accepts it.
# - When ad hoc: re-sign Sparkle's nested code, the framework, and the app with the same ad hoc identity (without
#   Hardened Runtime, since library validation rejects ad hoc frameworks on macOS).
team_of() { codesign -dv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p'; }
sign_dev_id() {
    if [ -n "$KEYCHAIN" ]; then
        codesign --force --timestamp --options runtime --preserve-metadata=identifier,entitlements \
            --keychain "$KEYCHAIN" --sign "$DEVELOPER_ID" "$1"
    else
        codesign --force --timestamp --options runtime --preserve-metadata=identifier,entitlements \
            --sign "$DEVELOPER_ID" "$1"
    fi
}

if [ -n "$DEVELOPER_ID" ]; then
    echo "Developer ID: signing embedded frameworks and app inside-out"
    for FW in "$APP"/Contents/Frameworks/*.framework; do
        [ -d "$FW" ] || continue
        find "$FW" -depth \( -name "*.xpc" -o -name "*.app" -o -perm -u+x -type f -path "*/Versions/*/Autoupdate" \) | \
            while IFS= read -r ITEM; do
                sign_dev_id "$ITEM"
            done
        sign_dev_id "$FW"
    done
    for DYLIB in "$APP"/Contents/Frameworks/*.dylib; do
        [ -f "$DYLIB" ] || continue
        if [ -n "$KEYCHAIN" ]; then
            codesign --force --timestamp --options runtime --keychain "$KEYCHAIN" --sign "$DEVELOPER_ID" "$DYLIB"
        else
            codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID" "$DYLIB"
        fi
    done
    sign_dev_id "$APP"
elif [ "$(team_of "$APP")" = "not set" ] || [ -z "$(team_of "$APP")" ]; then
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
codesign --verify --deep --strict --verbose=2 "$APP"
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
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "$DEVELOPER_ID" ]; then
    if [ -n "$KEYCHAIN" ]; then
        codesign --force --timestamp --keychain "$KEYCHAIN" --sign "$DEVELOPER_ID" "$DMG"
    else
        codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
    fi

    if [ -n "$APPLE_NOTARY_KEY_FILE" ] || [ -n "$NOTARY_PROFILE" ]; then
        echo "Notarizing (takes a few minutes)…"
        NOTARY_JSON="$OUT/notary.json"
        set +e
        if [ -n "$APPLE_NOTARY_KEY_FILE" ]; then
            if [ -z "$APPLE_NOTARY_KEY_ID" ] || [ -z "$APPLE_NOTARY_ISSUER_ID" ]; then
                echo "APPLE_NOTARY_KEY_FILE is set, but APPLE_NOTARY_KEY_ID or APPLE_NOTARY_ISSUER_ID is missing." >&2
                exit 1
            fi
            xcrun notarytool submit "$DMG" \
                --key "$APPLE_NOTARY_KEY_FILE" \
                --key-id "$APPLE_NOTARY_KEY_ID" \
                --issuer "$APPLE_NOTARY_ISSUER_ID" \
                --wait --output-format json > "$NOTARY_JSON"
        else
            xcrun notarytool submit "$DMG" \
                --keychain-profile "$NOTARY_PROFILE" \
                --wait --output-format json > "$NOTARY_JSON"
        fi
        NOTARY_RC=$?
        set -e
        cat "$NOTARY_JSON"

        if command -v jq >/dev/null 2>&1; then
            SUB_ID=$(jq -r '.id // empty' "$NOTARY_JSON" 2>/dev/null || true)
            STATUS=$(jq -r '.status // empty' "$NOTARY_JSON" 2>/dev/null || true)
        else
            SUB_ID=$(/usr/bin/python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("id",""))' "$NOTARY_JSON" 2>/dev/null || true)
            STATUS=$(/usr/bin/python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("status",""))' "$NOTARY_JSON" 2>/dev/null || true)
        fi

        if [ "$NOTARY_RC" -ne 0 ] || [ "$STATUS" != "Accepted" ]; then
            if [ -n "$SUB_ID" ]; then
                echo "::group::Notarization log ($SUB_ID)"
                if [ -n "$APPLE_NOTARY_KEY_FILE" ]; then
                    xcrun notarytool log "$SUB_ID" \
                        --key "$APPLE_NOTARY_KEY_FILE" \
                        --key-id "$APPLE_NOTARY_KEY_ID" \
                        --issuer "$APPLE_NOTARY_ISSUER_ID" || true
                else
                    xcrun notarytool log "$SUB_ID" --keychain-profile "$NOTARY_PROFILE" || true
                fi
                echo "::endgroup::"
            fi
            echo "::error::Notarization failed (status: ${STATUS:-unknown})" >&2
            rm -f "$NOTARY_JSON"
            exit 1
        fi
        rm -f "$NOTARY_JSON"

        xcrun stapler staple "$DMG"
        xcrun stapler validate "$DMG"
        spctl --assess --type open --context context:primary-signature --verbose "$DMG"
    else
        echo "Not notarized: set APPLE_NOTARY_KEY_FILE (with APPLE_NOTARY_KEY_ID and APPLE_NOTARY_ISSUER_ID) or NOTARY_PROFILE."
    fi
else
    echo "Not notarized: set DEVELOPER_ID and notarization credentials for a DMG others can open."
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
