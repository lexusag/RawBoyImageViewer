# RawBoy Viewer — Plan

A fast photo viewer and culling tool that you mostly drive with the mouse. It comes to macOS first and Windows later, and it supports touch.
It is part of the RawBoy family (repo `lexusag/RawBoy`). It follows RawBoy's design system and file formats, so that a
future **RawBoy desktop** can reuse it as its browser, the way RawBoy Web has a Browser tab.

**Status (2026-11-14):** M0–M8 are done, plus folder watching, crop, the licence and auto-update.
**v0.1 is out as a pre-release** ([releases](https://github.com/lexusag/RawBoyImageViewer/releases)): universal
(Intel and Apple Silicon), signed with the owner's free Personal Team, not notarized. Next steps are in §10.

## Decisions

| Topic | Decision |
|---|---|
| Name | **RawBoy Viewer**, bundle id `app.rawboy.viewer` (follows the `app.rawboy.*` scheme) |
| Stack | Native Swift (SwiftUI + AppKit where needed), XcodeGen, one local Swift package. Windows port comes later. |
| Minimum OS | macOS 15+ |
| Distribution | Direct download: a DMG from this repository's GitHub Releases, with Sparkle auto-updates. No sandbox. Notarized once the owner joins the paid Apple Developer Program; until then signed with the free Personal Team (others open it with right-click › Open). |
| Repository and licence | Public; MIT |
| RAW | Show the embedded camera preview instantly. Full RAW render on zoom or on request (see §4) |
| Editing | Culling plus light, lossless operations: rotate and crop, both kept in the sidecar. No pixel adjustments: that is RawBoy's job. |
| Metadata | XMP sidecars, **in the same format as RawBoy Browser** (§5). Rotation and crop in RawBoy's own fields, so RawBoy opens the photo the same way. |
| Delete | `⌘⌫` moves to the macOS Trash (the Finder shortcut; plain `⌫` means previous photo), with undo. **Move rejects to bin** (`_bin` subfolder) works as in RawBoy Browser. |
| Storage | The photo library lives in a cloud sync folder, so online-only files need special handling (§6) |
| Design | RawBoy's "Darkroom Bench" system (RawBoy `DESIGN.md`): same tokens, one amber accent, a neutral photo area |
| Voice | Like RawBoy: plain, short, factual British English ("colour"), numbers over adjectives |

---

## 1. Design system (shared with RawBoy)

The viewer uses RawBoy's tokens unchanged, in `RawBoyBrowseKit/DesignTokens.swift`. `tools/check-design-tokens.sh`
compares them with RawBoy's `DESIGN.md` front matter, so the two can't drift apart.

| Token | Value | Use in the viewer |
|---|---|---|
| ink-black | `#121212` | Window and photo background (neutral, never tinted) |
| graphite-surface | `#1c1c1e` | Edge panels, sidebar, rating bar |
| graphite-raised | `#26262a` | Buttons, hovered rows, thumbnail cells |
| hairline | `#333338` | Panel borders, row dividers |
| paper-white / ash-muted | `#ececec` / `#9a9aa2` | Text / labels, hints, EXIF keys |
| safelight-amber + amber-ink | `#e8a33d` + `#1a1206` | **The one accent:** current thumbnail, selected segment, primary action, focus ring, pick flag, stars |
| warning-red | `#ff6b6b` | Reject flag, errors, "can't open" |

- **Type:** the system font. Body 14, labels 12, titles 18.
- **Radii:** chip 6, segment 7, control 8, card 12.
- **Elevation:** flat tonal layers with hairline borders. A shadow appears only on floating things (edge panels, menus, the crop toolbar).
- **Edge panels are opaque `graphite-surface`, not translucent blurred glass:** RawBoy's rule is "don't tint, glow or
  colour anything around the photo", and a vibrancy blur takes on the photo's colours.
- **Histogram, clipping warning, rating badges:** ported from RawBoy (same colours and rules).
- **Native controls** (checkboxes, sliders) take the amber through the `AccentColor` asset.
- **Icon:** RawBoy's logo in the viewer's colours (blue `#4A86E8`, yellow lens), `branding/viewer.svg`, made into the
  macOS icon by `swift tools/icons/make-icons.swift`. A proposal: two values to change.
- `pointer: coarse` behaves the same as in RawBoy: touch input makes targets larger (at least 44 pt). Planned for the
  Windows port.

---

## 2. Interaction model

The image fills the screen. Everything else sits hidden at the screen edges and appears only when the cursor (or a finger) asks for it.

```
                ┌──────────── TOP: Browser strip ────────────┐
                │ breadcrumb · filmstrip (the wheel scrolls it)│
   ┌────────┐   └─────────────────────────────────────────────┘   ┌──────────┐
   │ LEFT:  │                                                     │ RIGHT:   │
   │ Action │                    IMAGE                            │ Details  │
   │ menu   │                                                     │ panel    │
   └────────┘   ┌───────────────────────┬─────────────────────┐   └──────────┘
                │  ◀ PREV (left half)   │   NEXT (right half) ▶│  ← bottom band
                └───────────────────────┴─────────────────────┘
```

### Edge zones (built as planned, `EdgeZones`, unit-tested)
- **Trigger strip:** the outer 8 pt of each edge, after a 120 ms dwell, so that passing over an edge doesn't flicker a panel open.
- **Stays open:** while the cursor is over the panel or within 24 pt of it; it closes 300 ms after the cursor leaves.
- **Overlay, not push:** panels float over the image. **Pin** keeps a panel open and the image fits beside it. Pins are remembered.
- **Corner dead zones (24 pt)** so two panels never open at once.
- **Bottom band (lower ~12%, only when the photo fits):** chevron cursors, a click goes to prev or next, holding keeps
  advancing (after 400 ms), with a "5 / 72" counter. Off when zoomed in, so dragging to pan never changes the photo.

### macOS fullscreen vs. the system menu bar and Dock
A custom borderless window covers the screen, with `presentationOptions = [.hideMenuBar, .hideDock]` while it's the key
window. Works on one display. **Multi-display hasn't been tested** (§10).

### Keyboard (matches RawBoy Browser wherever both have the action)
Letters match the physical key, so they work on a Ukrainian or other non-Latin layout. Everything is listed in the app's
Help (`⌘/` or `?`).

| Keys | Action | Source |
|---|---|---|
| `←` `→` (`↑` `↓` in the grid) | Previous / next | RawBoy Browser |
| `Space` / `⌫` | **Viewer:** next / previous photo | new |
| `Return`, `Space`, double-click | **Grid:** open photo or folder tile | RawBoy Browser |
| `Esc`, `G`, `Return` | **Viewer:** close the panels, then back to the grid | RawBoy Browser (+ Return) |
| `Z`, double-click | Fit ↔ 1:1 at the pointer | RawBoy Browser |
| Press and hold | 1:1 at the pointer while held, drag to look around | new |
| `1`–`5`, `0` | Stars (the same number again clears them), no stars | RawBoy Browser |
| `P` / `X` / `U` | Pick / Reject / Unflag (the same key again unflags) | RawBoy Browser |
| `⌘Z` | Undo the last rating, rotation, crop, or move to `_bin`, a folder or the Trash | RawBoy Browser |
| `R` | Real RAW preview instead of the camera's embedded preview | RawBoy Browser |
| `E` | The external editor (darktable when installed; Settings can choose another) | RawBoy Browser |
| `J` | Clipping warning (or click the histogram) | new |
| `K` | Crop | new |
| `S` / `C` | Slideshow / Compare | new |
| `[` `]` | Rotate left / right | new |
| `I` / `M` / `B` / `Tab` | Details / actions / filmstrip / hide every panel | new |
| `⌘⌫` · `⇧⌘E` · `⌥⌘C` | Move to Trash · Export · Copy the photo | new |
| `⌘/`, `?` | Help | RawBoy (`HelpDialog`) |

- **Auto-advance:** in the viewer, rating moves on to the next photo, as in RawBoy Browser (Photo menu, on by default).
- **Mouse wheel:** previous/next while the photo fits, zoom once zoomed in (Settings: always zoom). After zooming back
  out to fit, the wheel waits 0.4 s before changing photos.

### Touch and trackpad
Rule: **nothing works by hover only.** Every hover reveal also has a key.

| Action | Mouse | Trackpad (Mac) | Touchscreen (Windows later) |
|---|---|---|---|
| Next / prev | bottom band, wheel | two-finger swipe | horizontal swipe |
| Zoom | wheel (zoomed in), double-click, hold | pinch, smart-zoom double-tap | pinch, double-tap |
| Reveal panel | edge hover | — | swipe in from that edge |
| Toggle all UI | `Tab` | — | single tap on image |
| Select / context | ⌘-click, right-click | two-finger click | long-press (as in RawBoy Browser) |

Every input becomes a `ViewerCommand` (RawBoyBrowseKit), so the Windows port maps its own pointer and touch events
onto the same commands. (The planned `InputRouter` object turned out unnecessary.)

---

## 3. Screens (as built)

### A. Browser (the start screen)
- **Sidebar:** Favourites (star in the toolbar, or right-click a folder), Recent, Places (home folders, iCloud Drive,
  `~/Library/CloudStorage`, other volumes) as lazy folder trees.
- **Grid** with resizable thumbnails; badges: stars, pick, reject (faded), RAW / RAW+ (pair), XMP, ☁︎ online-only.
  **Subfolders as tiles** with a way up, off by default (folder button); `⌘↑` goes up.
- **A RAW + JPEG pair is one photo**, as in RawBoy Browser (`PhotoGroups`).
- **Sort:** shoot date (EXIF, else file date, undated last by name) or name, remembered: RawBoy's `PhotoOrder`.
- **Selection:** click, ⌘-click, Shift-click, arrows, `⌘A`, `Esc`. Ratings apply to the whole selection, and one undo takes them back.
- **Rating bar** under the grid: stars, Pick, Reject on the selection; filter All / Picks / Unflagged / Rejects and by
  stars; Move rejects to `_bin`, Bin (restore).
- **Search:** `⌘F`, by name.
- **Right-click a photo:** open, rotate, export, copy / move to a folder, copy, share, show in Finder, Trash.
- **The folder is watched:** other apps' new or removed photos and changed sidecars show up by themselves.

### B. Full-screen viewer
Fit to screen; `Z` / double-click toggle 1:1; press and hold for a temporary 1:1. A rating badge sits in the bottom-left
corner when the photo is rated.

### C. Right edge: details panel
Histogram (RawBoy's) with shadow/highlight shares, click for the clipping warning; rating control; exposure in one line;
camera, lens (or why it's missing), date, serial; shutter, aperture, ISO, compensation, focal length (35 mm terms),
mode, metering, flash, white balance; file, folder, position, size, date; pixel size, cropped size, "shown from" (camera
JPEG or developed raw), colour profile, bit depth; GPS with Show in Maps; artist, copyright, software; sidecars.

### D. Left edge: action menu
Cull (stars, Pick, Reject, Unflag, next photo after rating, Undo) · View (zoom, window, clipping, real preview,
slideshow, compare, hide panels) · Go to (first, last) · Transform (rotate, crop) · Output (export, copy, share) ·
Files (copy to, move to, Show in Finder, Trash) · Edit elsewhere (the external editor) · Viewer (close).

**Dropped from the reference app:** effects, colour-depth reduction, sepia/negative, red-eye, draw board, clone & heal,
print. RawBoy and darktable do the real editing.

### E. Top edge: browser strip
Breadcrumb (each part opens that folder in the browser), the folder's filmstrip with ratings, the current photo
centred; the mouse wheel scrolls it.

### F. Compare
2–4 photos side by side (2 × 2 for four), zoom, pan and hold in sync (`SharedZoom`). With two: click the better one and
the next photo takes the other place; ← → step through the challengers. Rating keys rate the chosen photo (amber frame).

### G. Crop tool
Over the whole photo: corners and edges resize, inside moves; RawBoy's aspect ratios (Free, Original, 1:1, 5:4, 4:3,
3:2, 16:9) with a portrait switch; thirds; Return applies, Esc cancels. Photos RawBoy straightened are left to RawBoy.

### H. Settings, Help, slideshow
Settings: last folder at launch, the mouse wheel, slideshow speed, real preview, next photo after rating, updates,
external editor, the synced-folder Trash question, export folder, thumbnail cache. Help lists every key. Slideshow: 4 s
by default, crossfading (none with Reduce Motion).

---

## 4. Previews and RAW rendering

Same rules as RawBoy Browser, so that both apps show the same picture for the same file:
- **Embedded previews come first** (`EmbeddedPreviews`, ported from RawBoy with its tests): TIFF IFDs/SubIFDs, CR3
  boxes, the RAF header, a JPEG-stream scan as the fallback; lossless-JPEG sensor data is rejected.
- **Grid** uses an embedded JPEG of at least 400 px, the **viewer** one of at least 2560 px; else ImageIO decodes.
  Phone DNGs have none, and Adobe's JPEG XL DNGs only a 256 px one: ImageIO decodes those.
- A camera's 160 × 120 EXIF thumbnail is never used (`Thumbnailer.fits`): portrait photos have them letterboxed.
- **Real preview (`R`):**
  - **Phase 1 (done):** `CIRAWFilter` as shot, at screen size and at 1:1. Not RawBoy's look.
  - **Phase 2 (with RawBoy desktop):** RawBoy's own engine (LibRaw + the AgX develop shader, `RawBoyNative.xcframework`,
    the Metal shaders from `shaders/`). That needs a macOS slice of the iOS engine, which RawBoy desktop needs anyway.
- **Performance (measured):** a prefetched photo shows in 0–50 ms; prefetch ±3 ahead, 1 behind, in a 1.5 GB memory LRU;
  previews are converted to 8-bit BGRA off the main thread (16-bit raw previews cost ~100 ms otherwise).
- **Not done:** a tiled canvas. 1:1 shows one full-resolution layer; fine for 50 MP so far. Revisit if panning stutters.
- Thumbnails are cached on disk in `~/Library/Caches/RawBoy Viewer/Thumbnails`.

---

## 5. Sidecars (the same format as RawBoy Browser)

- **File name `NAME.xmp`**, next to the raw, when a photo has no sidecar yet. This is what RawBoy Browser, Lightroom
  and Capture One use.
- **A photo that already has sidecars gets the rating in every one of them**, darktable's `NAME.RAF.xmp` and its
  duplicates included, as RawBoy Browser does (changed in M5 from "never write darktable's": consistency with RawBoy
  wins, and only the rating fields change, in place). The rating is read from the first sidecar, by name, that has one.
- `xmp:Rating` 0–5, and **reject = −1**. **Pick = `rawboy:Pick="1"`** in RawBoy's namespace `http://ns.rawboy.app/1.0/`.
- **Rotation:** `tiff:Orientation`, the photo's whole orientation, as Lightroom keeps it.
- **Crop, and RawBoy's rotation:** RawBoy's own fields in `rawboy:Develop` (`cropLeft`…`cropBottom`, `rotation`,
  `flipHorizontal`), written when a photo is cropped or already has RawBoy edits; every other RawBoy edit is kept as it
  is. RawBoy's turn wins when reading. RawBoy reads these with its "Edits in sidecars" setting on.
- **Only these fields are edited, in place. Everything else is kept byte for byte.**
- **Colour labels:** RawBoy has none yet. Leave them out until RawBoy Browser adds `xmp:Label` too, then do both together.
- **Bin:** "Move rejects to bin" moves rejects, their sidecars and same-name JPEGs into `_bin/`; **Bin** restores them, as
  in RawBoy Browser. The folder scan skips `_bin`.
- **Ported, not reinvented** (with RawBoy's test files): `XmpSidecar`, `EmbeddedPreview`, `CaptureDate`, `PhotoGroups`,
  `PhotoOrder`, `Histogram`, `CropMath`, the edits geometry. They live in `RawBoyBrowseKit`, meant to move into the
  RawBoy repo for RawBoy desktop.

---

## 6. Cloud sync folders

Most sync clients use macOS File Provider, so a file can be a **dataless placeholder**: reading any byte of it downloads it.
- **Done:** scanning reads metadata only (the ubiquitous-item status and `SF_DATALESS`); online-only files get a ☁︎ and
  no thumbnail or date read; opening one downloads it; prefetch downloads only the direct neighbours.
- **Done:** sidecar writes are atomic; FSEvents watches the open folder and re-reads sidecars changed elsewhere
  (RawBoy Web, darktable, another computer), never overwriting a change made here a moment ago.
- **Done:** the first Trash in a cloud folder asks first (it deletes on every device); `_bin` is the safer culling path.
- **Not done:** a "Download folder" action; the prefetch-distance setting (fixed at ±1 for online-only files);
  flagging sync conflict copies (`NAME (conflicted copy).xmp`).

---

## 7. Architecture (as built)

```
RawBoyImageViewer/
├── App/                 entry point, AppDelegate (Finder, keys, launch), AppModel, Updater (Sparkle), Trace, icon
├── Config/              signing (ad hoc; Signing.local.xcconfig, git-ignored, names this Mac's certificate)
├── Features/
│   ├── Browser/         model, toolbar, grid, sidebar
│   ├── Viewer/          session, window, root view, canvas, keys, crop tool
│   ├── Panels/          details, actions, browser strip, histogram
│   ├── Culling/         CullingStore (ratings, rotation, crop, undo, bin, Trash), file actions, rating control
│   ├── Compare/  Help/  Settings/
├── Theme/               RawBoy tokens as SwiftUI/AppKit colours, button styles
├── Packages/            RawBoyBrowseKit (pure Swift, portable) · ViewerImaging (ImageIO, Core Image) · ViewerFiles
├── branding/  docs/  tools/   (icon source, releasing guide and notes, smoke tests, release, icons, tokens check)
├── PLAN.md  CLAUDE.md  README.md  LICENSE  appcast.xml (the update feed)
```
- XcodeGen (`project.yml`), like RawBoy iOS; the `.xcodeproj` is git-ignored. CI: lint, package tests, app build.
- 110 unit tests (Swift Testing). `tools/smoke.sh` drives the debug app through a folder for timing and checks
  (`CULL`, `M7`, `WATCH`, `CROP` scripts, on copies only) and draws panels to PNG.

---

## 8. Milestones

| # | Milestone | Result |
|---|---|---|
| M0 ✅ | Repo setup | XcodeGen project, packages, tokens, swift-format (not SwiftLint: it ships with Xcode), GitHub Actions, CLAUDE.md, README |
| M1 ✅ | Core viewer | Open a folder or file (Finder's Open With too), fit/1:1, pan, keys, prefetch; menu bar and Dock hidden on one display |
| M2 ✅ | Edge zones | Zone state machine (unit-tested), panels with pin, bottom prev/next band, keys I/M/B/Tab/Esc |
| M3 ✅ | Browser | Sidebar, grid, RAW+JPEG grouping, sort, search, selection, disk thumbnail cache, RawBoy's preview and date parsers, cloud placeholders |
| M4 ✅ | Details panel | EXIF, RawBoy's histogram and clipping warning |
| M5 ✅ | Culling | Ratings in RawBoy's format, auto-advance, undo, `_bin`, Trash, rating bar and filters |
| M6 ✅ | Actions | Lossless rotate, export, copy / move to, copy, share, right-click menu |
| M7 ✅ | Real preview + Compare | CIRAWFilter real preview, Compare 2–4 with synced zoom, slideshow |
| M8 ✅ | Ship | Settings, Help, VoiceOver, Reduce Motion, icon, `tools/release.sh` |
| After M8 ✅ | Owner's requests | Folder watching; crop in RawBoy's fields; subfolder tiles, favourites, hold-to-zoom, Return to the browser, fuller EXIF, filmstrip wheel, portrait thumbnails (from trying the app); MIT; public repo; Personal Team signing; Sparkle; **v0.1 pre-release** |
| Later | RawBoy desktop | Move RawBoyBrowseKit into the RawBoy repo; real preview through RawBoy's engine; Open in RawBoy / Send to Auto |
| Later | Windows | Port the UI. RawBoyBrowseKit serves as the portable spec |

---

## 9. Items for the RawBoy repo (not this one)
- **Accent colour mismatch:** iOS Pro tints with `#FFB74D` (`ios/Pro/ProApp.swift`), but `DESIGN.md` says `#e8a33d`. Pick one.
- **Crop and orientation (done in the viewer):** the viewer writes RawBoy's own fields, so nothing new is needed in
  RawBoy. RawBoy doesn't read `tiff:Orientation`; reading it (for photos turned in Lightroom or here before a crop)
  would make the two agree in more cases.
- **Colour labels (`xmp:Label`):** add them to both apps together, or to neither.

## 10. Next

**Needs the owner:**
- **Notarizing:** the paid Apple Developer Program, a Developer ID certificate, notarization credentials; then
  `DEVELOPER_ID=… NOTARY_PROFILE=… PUBLISH=1 tools/release.sh <version>` (docs/releasing.md).
- **Back up the login keychain:** it holds the Sparkle key every update must be signed with.
- **Try it by hand where tests can't reach:** two displays (menu bar and Dock, edge strips); the crop tool's feel; Share;
  Move to with undo; Compare and the crossfade on screen; a sidecar cross-check with RawBoy Web on the same folder.

**Backlog (not done, by value):**
1. Cloud: "Download folder", flag sync conflict copies.
2. A sibling-folder switcher in the browser strip. (Dragging thumbnails or folders onto a folder in Places: done, `AppModel.beginDrag` / `dropOnPlace`; untried by hand.)
3. Search by stars, flag or camera in the `⌘F` field (the rating bar filters those today).
4. A tiled canvas, if 1:1 panning on very large files stutters.
5. Zero-copy (IOSurface) display, to remove the remaining 0–50 ms when showing a photo; colours must be checked by eye.
6. JPEG XL previews from RawBoy's parser (`findJxlPreview`), instead of ImageIO decoding those DNGs.
7. The Windows port, and RawBoy desktop (above).
