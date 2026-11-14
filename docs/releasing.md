# Releasing

`tools/release.sh <version>` builds an optimised Release of RawBoy Viewer into `build/release/RawBoy-Viewer-<version>.dmg`
(the build number defaults to the commit count).

## What only the owner can set up

1. **A Developer ID.** An Apple Developer Program membership gives a "Developer ID Application" certificate; install it
   in the keychain, then:
   ```sh
   security find-identity -v -p codesigning     # copy the "Developer ID Application: …" name
   ```
2. **Notarization credentials**, stored once in the keychain (an app-specific password from appleid.apple.com):
   ```sh
   xcrun notarytool store-credentials rawboy-notary --apple-id <apple id> --team-id <team id>
   ```
3. Then:
   ```sh
   DEVELOPER_ID="Developer ID Application: … (TEAMID)" NOTARY_PROFILE=rawboy-notary tools/release.sh 0.1
   ```

Without them the script still makes a DMG, signed ad hoc: it opens on this Mac, and on others only after
right-click › Open.

## Not done yet

- **Auto-update (Sparkle).** Needs a place for the update feed and the DMGs (GitHub Releases would do) and an EdDSA
  key pair kept by the owner. Decide where updates are hosted first.
- **A licence.** The repository has none yet (PLAN.md §10).
