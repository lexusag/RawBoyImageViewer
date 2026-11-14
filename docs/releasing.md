# Releasing and signing

`tools/release.sh <version>` builds an optimised Release of RawBoy Viewer into `build/release/RawBoy-Viewer-<version>.dmg`
(the build number defaults to the commit count). How far it gets depends on the Apple account behind it.

## What each kind of account allows

| | Ad hoc (no account) | Free account (Personal Team) | Apple Developer Program ($99 a year) |
|---|---|---|---|
| Certificate | none | "Apple Development" | "Developer ID Application" |
| Runs on the Mac that built it | yes | yes | yes |
| macOS keeps its permissions (drives, cloud folders) across new builds | no: each build is a new app | **yes** | yes |
| Opens on other Macs with a double-click | no: right-click › Open, or System Settings › Privacy & Security › Open Anyway | no: the same | **yes, once notarized** |
| Notarization | no | no | **yes** |

So a free account is worth using on your own Mac, but sharing the app with others needs the paid programme.

## 1. Sign your own builds with the free account (set up)

1. Xcode › Settings › Accounts: your Apple ID is there with its Personal Team (RawBoy's iOS builds use it).
2. Select the team › **Manage Certificates…** › an **Apple Development** certificate is listed (else **+** › Apple
   Development). Check from Terminal:
   ```sh
   security find-identity -v -p codesigning
   ```
3. `Config/Signing.local.xcconfig` (git-ignored, already on this Mac) names the team and identity:
   ```
   DEVELOPMENT_TEAM = PB2FFKSMC8
   CODE_SIGN_IDENTITY = Apple Development
   ```
   Then `xcodegen` and build as usual: Debug and `tools/release.sh` builds are signed by the team.

## 2. Notarize for everyone (needs the paid programme)

1. Join the Apple Developer Program with the same Apple ID (developer.apple.com/programs). The Personal Team becomes
   a paid team; the Team ID may change: update `Config/Signing.local.xcconfig`.
2. Xcode › Settings › Accounts › Manage Certificates › **+** › **Developer ID Application**.
3. An app-specific password at account.apple.com › Sign-In and Security › App-Specific Passwords, then store the
   notarization credentials once in the keychain:
   ```sh
   xcrun notarytool store-credentials rawboy-notary --apple-id <your Apple ID> --team-id <team id>
   ```
4. Release:
   ```sh
   DEVELOPER_ID="Developer ID Application: <name> (<team id>)" NOTARY_PROFILE=rawboy-notary tools/release.sh 0.1
   ```
   The script signs with a secure timestamp, notarizes the DMG (a few minutes), staples the ticket and checks it with
   `spctl`.

## 3. Publish a release, with auto-update

The app checks `appcast.xml` on `main` (Sparkle, `SUFeedURL`); each version's DMG is a GitHub release asset, signed
with the Sparkle key in the owner's login keychain (its public half is `SUPublicEDKey` in project.yml). **Back up the
login keychain:** without that key, installed copies can't take updates.

1. Write the notes: `docs/releases/v<version>.md`.
2. Publish (a clean, pushed `main`):
   ```sh
   PUBLISH=1 PRERELEASE=1 tools/release.sh 0.2      # drop PRERELEASE once notarized
   ```
   The script builds and signs, makes the DMG, signs it for Sparkle and adds it to `appcast.xml`, tags `v0.2`, creates
   the GitHub release with the DMG and the notes, then commits and pushes `appcast.xml`.
3. "Check for Updates…" in an older copy offers it.
