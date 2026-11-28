# RawBoy Viewer for Android

Android prototype of RawBoy Viewer for phones and tablets, using RawBoy's Darkroom Bench design tokens.

## What's included

- **Local folders via SAF:** pick any folder on internal storage, an SD card or a USB-C card reader. Listed with a single `DocumentsContract` query; raw embedded previews are read via random-access `FileChannel` without loading the whole file. Designed behind a `PhotoSource` interface so Google Drive can plug in later.
- **Fast grid & full-screen viewer:** embedded camera previews (`EmbeddedPreviews`, ported from `RawBoyBrowseKit`), disk thumbnail cache, device-sized memory LRU, RAW + JPEG grouping, sort by capture date or name, pinch and double-tap zoom, swipe down to close, EXIF details + RGB histogram (bottom sheet on phones, pinned right pane + top filmstrip + keyboard shortcuts on tablets).
- **Local database for culling (Room):** stars 0–5, Pick / Reject, auto-advance, undo, instant SQL filters (All / Picks / Unflagged / Rejects / minimum stars), optional `_bin` move and restore.
- **Write ratings to XMP on demand:** seeds the local DB from existing sidecars on first open of a folder, tracks unsynced ratings with a dot and count, and writes `xmp:Rating` + `rawboy:Pick` in place (preserving everything else byte for byte, tested against the Mac app's `Fixtures/Xmp/expected.json`). On conflicts where a sidecar was rated elsewhere, XMP wins by default (phone loses), with an option in the dialog to override.
- **Batch Send to RawBoy & RawBoy Auto:** targets `app.rawboy` (RawBoy Pro, single photo) and `app.rawboy.auto` (RawBoy Auto, batch via `ACTION_SEND_MULTIPLE` + `ClipData` + `FLAG_GRANT_READ_URI_PERMISSION`). Sends raws by default with a toggle to include paired JPEGs, and falls back to the system Share sheet if RawBoy isn't installed.

## Build & test

```bash
cd android
./gradlew :core:test          # runs the shared Mac XMP fixtures + core unit tests
./gradlew :app:assembleDebug  # outputs android/app/build/outputs/apk/debug/app-debug.apk
```

For a signed release APK, place a `keystore.properties` file in `android/` (git-ignored) with `storeFile`, `storePassword`, `keyAlias`, and `keyPassword`, then run `./gradlew :app:assembleRelease -PversionName=0.4.2 -PversionCode=60`. GitHub Releases set `versionName` from the tag and `versionCode` from the commit count automatically (configure the `ANDROID_KEYSTORE_*` repository secrets so releases share one signing key and update in place).
