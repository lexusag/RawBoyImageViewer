# RawBoy Viewer — Plan

A fast photo viewer and culling tool that you mostly drive with the mouse. It comes to macOS first and Windows later, and it supports touch.
It is part of the RawBoy family (repo `lexusag/RawBoy`). It follows RawBoy's design system and file formats, so that a
future **RawBoy desktop** can reuse it as its browser, the way RawBoy Web has a Browser tab.

## Decisions

| Topic | Decision |
|---|---|
| Name | **RawBoy Viewer**, bundle id `app.rawboy.viewer` (follows the `app.rawboy.*` scheme) |
| Stack | Native Swift (SwiftUI + AppKit where needed). Windows port comes later. |
| Minimum OS | macOS 15+ |
| Distribution | Direct download: a notarized DMG with Sparkle auto-updates. No sandbox. |
| RAW | Show the embedded camera preview instantly. Full RAW render on zoom or on request (see §4) |
| Editing | Culling plus light, lossless operations. No pixel adjustments: that is RawBoy's job. |
| Metadata | XMP sidecars, **in the same format as RawBoy Browser** (§5) |
| Delete | `⌘⌫` moves to the macOS Trash (the Finder shortcut; plain `⌫` means previous photo), with undo. **Move rejects to bin** (`_bin` subfolder) works as in RawBoy Browser. |
| Storage | The photo library lives in a cloud sync folder, so online-only files need special handling (§6) |
| Design | RawBoy's "Darkroom Bench" system (RawBoy `DESIGN.md`): same tokens, one amber accent, a neutral photo area |
| Voice | Like RawBoy: plain, short, factual British English ("colour"), numbers over adjectives |

---

## 1. Design system (shared with RawBoy)

The viewer uses RawBoy's tokens unchanged. They go in one `Theme.swift`, generated from or checked against RawBoy's
`DESIGN.md` front matter, so that the two can't drift apart.

| Token | Value | Use in the viewer |
|---|---|---|
| ink-black | `#121212` | Window and photo background (neutral, never tinted) |
| graphite-surface | `#1c1c1e` | Edge panels, sidebar |
| graphite-raised | `#26262a` | Buttons, hovered rows, thumbnail cells |
| hairline | `#333338` | Panel borders, row dividers |
| paper-white / ash-muted | `#ececec` / `#9a9aa2` | Text / labels, hints, EXIF keys |
| safelight-amber + amber-ink | `#e8a33d` + `#1a1206` | **The one accent:** current thumbnail, selected segment, primary action, focus ring, pick flag |
| warning-red | `#ff6b6b` | Reject flag, errors, "can't open" |

- **Type:** the system font (SF Pro on Mac, Segoe UI on Windows). Body 14, labels 12, titles 18.
- **Radii:** chip 6, segment 7, control 8, card 12.
- **Elevation:** flat tonal layers with hairline borders. A shadow appears only on floating things (edge panels, menus):
  `0 4px 24px rgba(0,0,0,.5)`.
- **Edge panels are opaque `graphite-surface`, not translucent blurred glass.** This changes the first draft:
  RawBoy's rule is "don't tint, glow or colour anything around the photo", and a vibrancy blur takes on the photo's colours.
- **Histogram colours, the clipping indicators and the stars/pick/reject badges** reuse RawBoy's `HistogramView` and
  Browser badges.
- **Logo:** a "viewer" variant drawn in the style of `branding/*.svg` (auto, camera, film, pro).
- `pointer: coarse` behaves the same as in RawBoy: touch input makes targets larger (at least 44 pt).

---

## 2. Interaction model

The image fills the screen. Everything else sits hidden at the screen edges and appears only when the cursor (or a finger) asks for it.

```
                ┌──────────── TOP: Browser strip ────────────┐
                │ breadcrumb · filmstrip · rating filter      │
   ┌────────┐   └─────────────────────────────────────────────┘   ┌──────────┐
   │ LEFT:  │                                                     │ RIGHT:   │
   │ Action │                    IMAGE                            │ Info     │
   │ menu   │                                                     │ panel    │
   └────────┘   ┌───────────────────────┬─────────────────────┐   └──────────┘
                │  ◀ PREV (left half)   │   NEXT (right half) ▶│  ← bottom band
                └───────────────────────┴─────────────────────┘
```

### Edge zones and how they behave
- **Trigger strip:** the outer 6–8 pt of each edge. A panel opens after a short dwell (about 120 ms) so that passing over an edge doesn't flicker it open.
- **Stays open:** while the cursor is over the panel or within a 24 pt grace margin around it. It closes about 300 ms after the cursor leaves.
- **Overlay, not push:** panels float over the image, so the image never reflows. **Pin** keeps a panel open and the image
  shrinks to fit beside it. Pins are remembered.
- **Corner dead zones (24 pt)** so two panels never open at once.
- **Bottom band (lower ~12% of the window, only when zoomed to fit):**
  - The cursor turns into a ◀ or ▶ chevron. A click goes to prev or next, and holding the button keeps advancing (repeating after 400 ms).
  - Shows a small "5 / 72" counter.
  - It turns off when zoomed in, so that dragging to pan never changes the image by accident.

### macOS fullscreen vs. the system menu bar and Dock ⚠️
In native fullscreen, the top edge shows the menu bar and the bottom edge can show the Dock. The plan: a custom borderless window
that covers the screen, with `presentationOptions = [.hideMenuBar, .hideDock]` while the viewer is active. This is the first spike
in M1. Edges shared between two monitors get a wider trigger strip, because the cursor has no "wall" to stop against there.

### Keyboard (matches RawBoy Browser wherever both have the action)
| Keys | Action | Source |
|---|---|---|
| `←` `→` (`↑` `↓` in the grid) | Previous / next | RawBoy Browser |
| `Space` / `⌫` | **Viewer:** next / previous photo (one hand on the keyboard, one on the mouse) | new |
| `Enter`, `Space`, click | **Grid:** open photo | RawBoy Browser |
| `Esc`, `G` | Back to the grid | RawBoy Browser |
| `Z`, double-click | 1:1 at the pointer, drag to pan | RawBoy Browser |
| `1`–`5`, `0` | Stars (the same number again clears them), no stars | RawBoy Browser |
| `P` / `X` / `U` | Pick / Reject / Unflag (the same key again unflags) | RawBoy Browser |
| `⌘Z` | Undo the last rating, move or delete | RawBoy Browser |
| `R` | Real RAW preview instead of the camera's embedded preview | RawBoy Browser |
| `E` | Open in RawBoy (once RawBoy desktop exists), else the external editor (darktable) | RawBoy Browser |
| `⌘/`, `?` | Help sheet | RawBoy (`HelpDialog`) |
| `I` / `M` / `B` / `Tab` | Info panel / action menu / browser strip / hide all | new |
| `[` `]` | Rotate left / right (lossless) | new |
| `⌘⌫` | Move to Trash | new (Finder's shortcut) |

- **Auto-advance:** in the photo view, rating moves on to the next photo, as in RawBoy Browser.
- Letter shortcuts match on the physical key, not the typed character, so they also work on a Ukrainian or other non-Latin
  layout. This is the same fix RawBoy made with `shortcutKey()`.

### Touch and trackpad
Rule: **nothing works by hover only.** Every hover reveal also has a gesture and a keyboard path.

| Action | Mouse | Trackpad (Mac) | Touchscreen (Windows later) |
|---|---|---|---|
| Next / prev | bottom band, wheel* | two-finger swipe | horizontal swipe |
| Zoom | wheel*, double-click | pinch, smart-zoom double-tap | pinch, double-tap |
| Reveal panel | edge hover | — | swipe in from that edge |
| Toggle all UI | `Tab` | — | single tap on image |
| Select / context | ⌘-click, right-click | two-finger click | long-press (as in RawBoy Browser) |

\*What the mouse wheel does (navigate or zoom) is a setting. The default is navigate when the image fits the screen and zoom when it is zoomed in.

All gestures go through one `InputRouter`, which turns them into commands. The Windows port maps its own pointer events onto the same commands.

---

## 3. Screens

### A. Browser (the start screen)
- **Sidebar:** Favorites, Recent folders, and the folder tree.
- **Grid** with resizable thumbnails. Badges show stars, pick/reject, a RAW + JPEG pair, ☁︎ online-only, and a sidecar indicator.
- **A RAW + JPEG pair is one photo**, as in RawBoy Browser (`PhotoGroups`).
- **Sort:** shoot date (the default: EXIF date, else the file date, undated photos last by name) or file name, remembered.
  Same rules as RawBoy's `PhotoOrder`.
- **Selection:** ⌘-click, Shift-click, `⌘A`, `Esc`. Ratings apply to every selected photo, and one Undo takes them back.
- **Rating bar** under the grid (stars, Pick, Reject), as in RawBoy Browser.
- **One `⌘F` field** to search and filter: name, stars ≥, pick/reject, camera.
- **Dropped from the reference:** the wall of toolbar icons, the format dropdown, the fixed zoom box.

### B. Full-screen viewer
The image only, fit to screen. Double-click or `Z` toggles 1:1. The zoom % appears briefly, then fades.

### C. Right edge: info panel
- File, folder, size, dimensions, date taken.
- Camera, lens, focal length, aperture, shutter, ISO, bias. It handles missing fields cleanly: adapted manual lenses report no aperture.
- **Histogram** with clipping indicators, which can also overlay clipped areas on the image.
- Stars and pick/reject, editable here.
- Sidecar status: which file it is, whether RawBoy or RawBoy Auto edits are inside it (`rawboy:Develop` / `rawboy:Auto`), and whether darktable's
  sidecar exists.
- Optional: GPS mini-map, the editor that produced the file.

### D. Left edge: action menu (big, icon-first, grouped)
1. **Cull:** ★1–5, Pick, Reject, Unflag
2. **Transform (lossless):** rotate (orientation only), crop (saved to the sidecar, applied on export)
3. **Output:** Export / Resize… (presets such as "3000 px long edge"), copy, Share
4. **Edit elsewhere:** Open in RawBoy, send to RawBoy Auto (once desktop exists), open in an external editor (darktable by default)
5. **Files:** Reveal in Finder, Copy to… / Move to… (with recent destinations), Move rejects to bin, Move to Trash, Download (cloud)
6. **View:** Slideshow, Compare (2-up / 4-up), Real preview (R)

**Dropped from the reference:** effects (bump map, oil painting, sketch, frame mask), colour-depth reduction, sepia/negative,
red-eye, draw board, clone & heal, print. RawBoy and darktable do the real editing.

### E. Top edge: browser strip
Breadcrumb path (click any segment to jump there) and a sibling-folder switcher. A filmstrip with the current photo centred. A rating filter.
Dragging thumbnails onto a folder moves the files.

### F. Compare mode
2 or 4 photos with synced zoom and pan. Click the one to keep and the next candidate takes the other place.

---

## 4. Previews and RAW rendering

Same rules as RawBoy Browser, so that both apps show the same picture for the same file:
- **Embedded previews come first:** the camera's JPEG, found by walking TIFF IFDs/SubIFDs, CR3 boxes and the RAF header.
  Never the raw decoder. A JPEG-stream scan is the fallback. Lossless-JPEG sensor data is rejected.
- **Grid** uses the smallest preview ≥ 400 px. The **viewer** uses the smallest ≥ 2560 px.
- DNG 1.7 JPEG XL previews are supported too: macOS 15 decodes JXL through ImageIO.
- **Real preview (`R`)** renders the RAW itself:
  - **Phase 1 (M7):** `CIRAWFilter` as shot. It's quick to build, but its colours differ from RawBoy's.
  - **Phase 2 (with RawBoy desktop):** develop as shot with **RawBoy's own engine** (LibRaw + the AgX develop shader through
    `RawBoyNative.xcframework` and the Metal shaders generated from `shaders/`). Then "real preview" looks exactly like
    RawBoy. This needs a macOS slice of the iOS engine, which RawBoy desktop needs anyway.
- Performance targets:
  - < 50 ms to switch to a prefetched photo.
  - Prefetch ±3 photos in the browsing direction, kept in a memory LRU of about 1.5 GB.
  - A tiled canvas, so panning a 50 MP GFX file at 1:1 stays smooth.
  - The thumbnail disk cache lives in `~/Library/Caches/RawBoy Viewer`.

---

## 5. Sidecars (the same format as RawBoy Browser)

- **File name `NAME.xmp`**, next to the raw. This is what RawBoy Browser, Lightroom and Capture One use.
  darktable's own `NAME.RAF.xmp` is **read** for display and never written: darktable owns that file and rewrites it.
- `xmp:Rating` 0–5, and **reject = −1**.
- **Pick = `rawboy:Pick="1"`** in RawBoy's namespace `http://ns.rawboy.app/1.0/`.
- **Only RawBoy's fields are edited, in place. Everything else is kept byte for byte**, including `rawboy:Develop` and `rawboy:Auto`
  (RawBoy and RawBoy Auto edits). The viewer shows that these exist but never changes them.
- Crop and rotation from the viewer: `rawboy:Crop` / orientation. **Agree on the format with RawBoy first**, so RawBoy
  can read the crop instead of ignoring it.
- **Colour labels:** RawBoy has none yet. Leave them out until RawBoy Browser adds `xmp:Label` too, then do both together.
- **Bin:** "Move rejects to bin" moves rejects, their sidecars and same-name JPEGs into `_bin/`. **Bin** restores them, as in
  RawBoy Browser. The folder scan skips `_bin`. Separately, `⌘⌫` sends the selection to the Trash.
- **Port, don't reinvent:** port RawBoy's `engine/browse/XmpSidecar.ts`, `EmbeddedPreview.ts`, `CaptureDate.ts`,
  `ui/browser/PhotoGroups.ts` and the existing `ios/Auto/PhotoOrder.swift` to Swift, **with the same test files**.
  Later these move into a shared `RawBoyBrowseKit` Swift package that RawBoy desktop and iOS can both use.

---

## 6. Cloud sync folders

Most of these sync clients use macOS File Provider, which means a file can be a **dataless placeholder**. Reading any byte of it triggers a download.
- **Scanning must never trigger a download.** The scanner reads metadata only: the ubiquitous-item status and the `SF_DATALESS` flag.
  Online-only files get a ☁︎ badge and a placeholder thumbnail.
- **Downloads only on intent:**
  - Opening a file downloads it and shows a progress ring.
  - Prefetch downloads at most ±1 neighbor of a cloud-only file. This is a setting: Off / ±1 / ±3.
  - The left menu has "Download folder".
- **Thumbnail cache is local**, keyed by relative path + size + mtime.
- **Sidecar writes are atomic** (write to a temp file, then rename), so the sync client never uploads a half-written sidecar. Conflict copies
  (`NAME (conflicted copy).xmp`) are flagged in the info panel, never silently merged.
- **Sidecars change elsewhere:** FSEvents watches the folder and re-reads sidecars that change, because ratings may be edited elsewhere
  (RawBoy Web, Windows, darktable) and synced back.
- **Trash:** Trash in a synced folder deletes the file from the cloud and every device. The first time, a one-time notice says so.
  The `_bin` workflow is the safer default for culling.

---

## 7. Architecture

```
RawBoyImageViewer/
├── App/                      SwiftUI scenes, settings, menu commands, Help sheet
├── Features/
│   ├── Browser/              sidebar, grid, selection, rating bar
│   ├── Viewer/               ImageCanvas (NSView + tiled CALayer/Metal), EdgeZoneController, InputRouter
│   ├── Panels/               InfoPanel, ActionMenu, BrowserStrip
│   └── Compare/
├── Packages/
│   ├── RawBoyBrowseKit       ← pure Swift: XMP sidecar, embedded preview parser, capture date, photo groups/order,
│   │                           EdgeZone state machine, commands.  Destined for RawBoy repo as shared code.
│   ├── ViewerImaging         ← ImageIO, CIRAWFilter, thumbnails, histogram, caches (Apple-only)
│   └── ViewerFiles           ← scanning, cloud placeholders, FSEvents, Trash/_bin, undo
├── Theme/                    RawBoy design tokens
├── CLAUDE.md  DESIGN.md (→ links RawBoy's)  CHANGELOG.md  docs/
```
- Project generated with **XcodeGen** (`project.yml`), like RawBoy iOS. The `.xcodeproj` is git-ignored.
- Repo conventions follow RawBoy: `CLAUDE.md` for how the code fits together, `docs/` + `CHANGELOG.md` for user-visible changes,
  and the Help sheet updated along with the controls.

---

## 8. Milestones

| # | Milestone | Done when |
|---|---|---|
| M0 | Repo setup | XcodeGen project, packages, Theme tokens, SwiftLint, GitHub Actions (build + tests), CLAUDE.md, README, license |
| M1 ✅ | Core viewer | Open a folder or file (including "Open With" from Finder), fit/1:1, pan, keys, prefetch. **Fullscreen menu-bar/Dock spike**: works on one display (menu bar + Dock hidden while the viewer is key); multi-display untested |
| M2 ✅ | Edge zones | Zone state machine (unit-tested), panels with pin, bottom prev/next band, keys I/M/B/Tab/Esc. Panels hold what exists so far (details without EXIF, view/go/file actions, breadcrumb + filmstrip); touch swipe-in waits for the Windows port (commands exist) |
| M3 ✅ | Browser | Sidebar (recent, places, cloud storage, volumes, lazy tree), grid with sizes, RAW+JPEG grouping, sort by shoot date/name, name search, selection, disk thumbnail cache, embedded-preview and capture-date parsers (ported from RawBoy + its tests), cloud placeholders never downloaded by browsing. Moved on: rating bar and rating filter (M5), sibling-folder switcher in the top strip (later) |
| M4 | Info panel | EXIF, histogram + clipping, sidecar status |
| M5 | Culling | Ratings/pick/reject in RawBoy's XMP format, auto-advance, undo, `_bin`, Trash. **Cross-check with RawBoy Web on the same folder** |
| M6 | Actions | Lossless rotate, crop (format agreed with RawBoy), export presets, external editor, copy/move |
| M7 | Real preview + Compare | `CIRAWFilter` real preview, compare 2-up/4-up, slideshow |
| M8 | Ship | Settings, Help sheet, accessibility (VoiceOver, reduced motion), notarization, Sparkle, viewer logo |
| Later | RawBoy desktop | Move RawBoyBrowseKit into the RawBoy repo; real preview through RawBoy's engine; Open in / Send to Auto |
| Later | Windows | Port the UI. RawBoyBrowseKit serves as the portable spec |

---

## 9. Items for the RawBoy repo (not this one)
- **Accent colour mismatch:** iOS Pro tints with `#FFB74D` (`ios/Pro/ProApp.swift`), but `DESIGN.md` says `#e8a33d`. Pick one.
- **Crop and orientation:** agree on a sidecar field the viewer writes and RawBoy reads.
- **Colour labels (`xmp:Label`):** add them to both apps together, or to neither.

## 10. Still open (decide before M8)
License, and whether to build for Apple Silicon only or as a universal binary.
