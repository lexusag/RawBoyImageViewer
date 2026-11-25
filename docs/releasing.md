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

Distribution outside the Mac App Store requires a **Developer ID Application** certificate (not *Apple Development* or
*Mac App Distribution*) and notarization with Apple (`xcrun notarytool`). App Sandbox stays off (`ENABLE_APP_SANDBOX:
NO`) so RawBoy Viewer can keep writing `.xmp` sidecars next to your photos; Hardened Runtime (`--options runtime`) and
secure timestamps (`--timestamp`) are applied inside-out to `Sparkle.framework` (including its nested XPC services,
`Updater.app`, and `Autoupdate`) and `RawBoy Viewer.app`.

### Create and export the Developer ID Application certificate

1. Join the Apple Developer Program with your Apple ID (`developer.apple.com/programs`).
2. Open **Xcode › Settings › Accounts**, select your paid team, click **Manage Certificates…**, click **+** and choose
   **Developer ID Application**.
3. Open **Keychain Access**, select **login** (left sidebar) › **My Certificates** (top tab), and find
   `Developer ID Application: <Your Name> (<TEAMID>)`. Expand the disclosure triangle to confirm its private key is
   nested under it.
4. Select the certificate, right-click › **Export "Developer ID Application: …"**, choose **Personal Information
   Exchange (.p12)**, save it as `rawboy-dev-id.p12`, and set a strong export password. *(Keep a backup in a password
   manager; you cannot re-download the private key from Apple.)*
5. Base64-encode the `.p12` for GitHub Secrets:
   ```sh
   base64 -i rawboy-dev-id.p12 | pbcopy
   ```

### Create an App Store Connect API key for notarization

Using an App Store Connect API key (`.p8` file, Key ID, Issuer ID) is preferred over an Apple ID + app-specific
password because it is not tied to your personal login and does not break when you change your Apple ID password.

1. Open [appstoreconnect.apple.com](https://appstoreconnect.apple.com) › **Users and Access › Integrations › App Store
   Connect API**.
2. Under **Team Keys**, click **+** (Generate API Key) with **Access: Developer**.
3. Copy the **Issuer ID** (top of the page) and the new key's **Key ID**.
4. Click **Download** to save `AuthKey_<KEYID>.p8` *(can only be downloaded once — store it safely alongside your
   `.p12`)*.
5. Base64-encode the `.p8` for GitHub Secrets:
   ```sh
   base64 -i AuthKey_<KEYID>.p8 | pbcopy
   ```

### Build, sign, and notarize locally on a Mac

With the Developer ID Application certificate in your login keychain:

```sh
IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -n 1)
DEVELOPER_ID="$IDENTITY" \
  APPLE_NOTARY_KEY_FILE=~/keys/AuthKey_<KEYID>.p8 \
  APPLE_NOTARY_KEY_ID=<KEYID> \
  APPLE_NOTARY_ISSUER_ID=<ISSUER_ID> \
  tools/release.sh 0.2
```

*(Alternatively, if you stored credentials in your login keychain with `xcrun notarytool store-credentials rawboy-notary`,
pass `NOTARY_PROFILE=rawboy-notary` instead of the `APPLE_NOTARY_*` variables.)*

The script signs Sparkle and the app inside-out with Hardened Runtime and secure timestamps, packs and signs the DMG,
notarizes it with Apple (printing the full `notarytool log` on rejection), staples and validates the ticket, and checks
Gatekeeper with `spctl`.

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

## 4. Or let CI build, sign, and notarize the DMG

`.github/workflows/release.yml` runs when a GitHub release is published (or by hand from the Actions tab, giving the
tag). It checks out the tag, runs `tools/release.sh <version>` on a macOS runner, verifies the app inside the DMG, and
attaches the DMG to the release. Create the release first (tag `v<version>`, notes from `docs/releases/v<version>.md`),
without `PUBLISH=1`:
```sh
gh release create v0.2 --title "RawBoy Viewer 0.2" --notes-file docs/releases/v0.2.md --prerelease
```

Repository secrets (**Settings › Secrets and variables › Actions**):

| Secret | Value |
|---|---|
| `MACOS_CERT_P12` | base64 of `rawboy-dev-id.p12` |
| `MACOS_CERT_PASSWORD` | password you chose when exporting the `.p12` |
| `APPLE_NOTARY_KEY` | base64 of `AuthKey_<KEYID>.p8` |
| `APPLE_NOTARY_KEY_ID` | the 10-character Key ID from App Store Connect |
| `APPLE_NOTARY_ISSUER_ID` | the UUID Issuer ID from App Store Connect |
| `SPARKLE_PRIVATE_KEY` | *(optional)* the Sparkle EdDSA private key (`generate_keys -x file`, in `build/SourcePackages/artifacts/sparkle/Sparkle/bin`): CI signs the DMG for Sparkle and commits `appcast.xml` to `main`. Without it the feed is left alone |

You do not need a separate secret for the signing identity name: the workflow reads the `Developer ID Application: …`
identity directly from the imported `.p12`.

- **Safety check:** if `MACOS_CERT_P12` is set, the workflow requires all four companion secrets (`MACOS_CERT_PASSWORD`,
  `APPLE_NOTARY_KEY`, `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID`) and fails if signing or notarization fails, so a
  misconfiguration never silently uploads an unnotarized DMG. If `MACOS_CERT_P12` is unset, it falls back to an ad-hoc
  signed DMG with a warning.
- Don't also run `PUBLISH=1 tools/release.sh` for the same version: CI would replace the DMG the feed was signed for.

### Troubleshooting

- **`No 'Developer ID Application' certificate found in MACOS_CERT_P12`:** you exported an *Apple Development* or *Mac
  App Distribution* certificate, or exported the certificate without its private key. Re-export from **My Certificates**
  in Keychain Access with the private key included.
- **Notarization status `Invalid`:** `tools/release.sh` automatically prints the full JSON log from
  `xcrun notarytool log <submission-id>` in the step output. The most common causes are a nested binary (such as inside
  `Sparkle.framework`) missing `--timestamp` or `--options runtime`.
- **Certificate renewal:** Developer ID Application certificates expire after 5 years. Existing notarized DMGs keep
  working because they carry a secure timestamp; create a new certificate, export a new `.p12`, and update
  `MACOS_CERT_P12` and `MACOS_CERT_PASSWORD`.

## Tags that RawBoy pins

RawBoy Desktop (`lexusag/RawBoy`, `ios/project.yml`) depends on this repository's libraries (RawBoyBrowseKit, ViewerFiles,
ViewerImaging, ViewerUI) by git tag, which needs `Package.swift` at the repository root. **v0.2.0 has none**; the root
manifest arrives with the next release, so RawBoy pins **v0.2.1 or later**. Every tag RawBoy uses must contain
`Package.swift`, and `tools/check-root-package.sh` (run by CI) keeps it in step with `Packages/Package.swift`. After
tagging, RawBoy's `project.yml` switches from the local path to `from: <tag>` (see its `docs/desktop.md`). Library API
changes that RawBoy depends on (`ViewerHost`, `ViewerOptions`, `PhotoHandOff`...) are a reason for a new tag.
