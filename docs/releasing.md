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

## 4. Or let CI build the DMG

`.github/workflows/release.yml` runs when a GitHub release is published (or by hand from the Actions tab, giving the
tag). It checks out the tag, runs `tools/release.sh <version>` on a macOS runner and attaches the DMG to the release.
Create the release first (tag `v<version>`, notes from `docs/releases/v<version>.md`), without `PUBLISH=1`:
```sh
gh release create v0.2 --title "RawBoy Viewer 0.2" --notes-file docs/releases/v0.2.md --prerelease
```
Repository secrets, all optional (without them the DMG is ad hoc signed: right-click › Open):

| Secret | What |
|---|---|
| `DEVELOPER_ID_CERT_P12`, `DEVELOPER_ID_CERT_PASSWORD` | the "Developer ID Application" certificate exported from Keychain Access as .p12, base64-encoded (`base64 -i cert.p12`), and its password |
| `DEVELOPER_ID` | the identity name: `Developer ID Application: <name> (<team id>)` |
| `NOTARY_APPLE_ID`, `NOTARY_PASSWORD`, `NOTARY_TEAM_ID` | Apple ID, its app-specific password and the team id: the DMG is notarized and stapled |
| `SPARKLE_PRIVATE_KEY` | the Sparkle EdDSA private key (`generate_keys -x file`, in `build/SourcePackages/artifacts/sparkle/Sparkle/bin`): CI signs the DMG and commits `appcast.xml` to `main`. Without it the feed is left alone |

Don't also run `PUBLISH=1 tools/release.sh` for the same version: CI would replace the DMG the feed was signed for.

## Tags that RawBoy pins

RawBoy Desktop (`lexusag/RawBoy`, `ios/project.yml`) depends on this repository's libraries (RawBoyBrowseKit, ViewerFiles,
ViewerImaging, ViewerUI) by git tag, which needs `Package.swift` at the repository root. **v0.2.0 has none**; the root
manifest arrives with the next release, so RawBoy pins **v0.2.1 or later**. Every tag RawBoy uses must contain
`Package.swift`, and `tools/check-root-package.sh` (run by CI) keeps it in step with `Packages/Package.swift`. After
tagging, RawBoy's `project.yml` switches from the local path to `from: <tag>` (see its `docs/desktop.md`). Library API
changes that RawBoy depends on (`ViewerHost`, `ViewerOptions`, `PhotoHandOff`...) are a reason for a new tag.
