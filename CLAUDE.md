# CLAUDE.md

Guidance for working on RawBoy Viewer. The plan, decisions and milestones are in `PLAN.md`; keep it current when a
decision changes.

## What it is

A mouse-first photo viewer and culling tool for macOS (Windows later, touch supported). It belongs to the RawBoy family
(`lexusag/RawBoy`, usually checked out at `../RawBoy`) and must stay consistent with it:

- **Design:** RawBoy's tokens ("The Darkroom Bench", RawBoy's `DESIGN.md`). One amber accent; the photo area stays neutral
  (`#121212`, nothing tinted, blurred or glowing around the photo); edge panels are opaque graphite, not translucent.
  Values live in `Packages/Sources/RawBoyBrowseKit/DesignTokens.swift`; `tools/check-design-tokens.sh` compares them with a
  RawBoy checkout. Don't add colours, fonts or gradients.
- **Behaviour:** keys, sidecars, previews and the `_bin` folder follow RawBoy Browser (`web/src/ui/browser/`,
  `web/src/engine/browse/` in RawBoy). When porting its logic, port its tests and test files too.
- **Voice:** plain, short, factual British English ("colour"), numbers over adjectives.
- Never name other viewer products in code, comments or UI text.

## Layout

- `project.yml`: XcodeGen spec. Run `xcodegen` after adding or removing files; the `.xcodeproj` is git-ignored.
- `App/`: entry point (`RawBoyViewerApp`, one `Window` scene so opening files never spawns windows), `AppDelegate`
  (Finder "Open With", Dock drops, a path on the command line, the last folder at launch; all held until the browser
  window is key), `AppModel` (the browser and the viewer, and what opens where), `Trace` (dev log).
- `Features/Browser/`: `MarqueeSelection` (rubber-band: a drag surface behind the cells, rectangle in content coordinates, auto-scroll by timer), `BrowserModel` (folder → `BrowsePhoto`s via `FolderScanner` + `PhotoGroups`, capture dates read
  in the background then one reorder, sort/filter/size/recent/last folder in UserDefaults `browser.*`, selection as in
  RawBoy Browser), `BrowserView` (toolbar, `Segmented`), `PhotoGrid` (LazyVGrid, keys, `ThumbnailStore` at 480 px),
  `GridEntry` (parent / folder / photo tiles: folders only with `showFolders`, off by default), favourites (UserDefaults
  `browser.favourites`, toolbar star or right-click `FolderMenu`), `Sidebar` (favourites, recent, places incl. ~/Library/CloudStorage and volumes, lazy folder tree). The viewer gets the browser's
  order (`AppModel.openViewer`) and hands back the photo it ended on. `Theme/`: tokens as SwiftUI/AppKit colours,
  RawBoy button styles.
- `Features/Viewer/`: `ViewerSession` (open folder, photo list from `PhotoGroups`, every `ViewerCommand`, load +
  prefetch through `ImageStore`, full resolution on zoom), `ViewerModel` (@Observable state the panels show and their
  `send`), `ViewerWindowController` (screen-filling borderless window ↔ titled window; owns `EdgeZones`, feeds it the
  pointer and wakes it at `nextDeadline`; pins saved in UserDefaults `viewer.pinnedEdges`), `ViewerRootView` (flipped,
  y down like `EdgeZones`: the canvas plus the three panels in NSHostingViews, slide/fade, panel frames),
  `ImageCanvasView` (AppKit + one `CALayer`; zoom/pan via `ZoomMath` inside `imageArea` = bounds minus pinned panels;
  bottom band via `BottomBand`, chevron cursors, hold-repeat, counter pill; press-and-hold peek at 1:1 (after
  `peekDelay`, at once on drag; release → fit); the wheel/trackpad don't change photos for `navigationPause` after
  zooming or panning, so zooming out to fit doesn't run on into the next photos; mouse/trackpad/keys → `ViewerCommand`),
  `ViewerKeys` (physical key codes).
- `Features/Culling/`: `FileActions` (AppModel: export sheet, Copy/Move to with recent destinations, clipboard,
  Share, for `actionTargets` = the viewer's photo or the browser's selection), `CullingStore` (orientations
  alongside ratings: rotate, undo, written with them; ratings by photo id, read from sidecars when a folder opens, written 0.4 s
  after a change through one serial chain, undo stack of ratings and file moves, `_bin` and Trash, synced-folder
  Trash notice, `autoAdvance`), `RatingControl` / `RatingBadge`. `AppModel` routes ⌘Z / ⌘⌫ (menus) to the viewer or
  the browser, and the browser's rating keys come through `AppDelegate`'s key monitor by key code.
- `Features/Viewer/CropTool.swift`: `CropToolState` (shared with the toolbar), `CropOverlayView` (AppKit drawing over
  the uncropped photo; `ViewerWindowController.beginCrop/endCrop`), `CropToolbar`. The canvas shows a crop through
  `contentsRect` (layers count from the bottom-left, crops from the top-left).
- `Features/Compare/`: `CompareSession` (2–4 panes; with two, choosing one brings the next challenger in the
  other; zoom shared through `SharedZoom`; rating keys on the chosen pane), `CompareWindowController` (screen-filling
  like the viewer, `ViewerWindow`, panes side by side or 2 × 2). Canvases there have `navigationEnabled = false`.
- `Features/Help/`: `HelpContent` (every key; keep it in step with the controls and README's tables), `HelpView`,
  `HelpWindow` (a floating panel, so it shows over the screen-filling viewer; ⌘/ and ? via `AppDelegate`).
- `Features/Settings/`: `SettingsKeys` (the few personal choices, read where they apply) and `SettingsView`.
- `App/Assets.xcassets`: the icon (made by `swift tools/icons/make-icons.swift` from `branding/viewer.svg`, RawBoy's
  logo in the viewer's colours) and the amber `AccentColor` for native controls.
- `Features/Panels/`: SwiftUI. `PanelCard` (RawBoy card + pin), `InfoPanel` (right; `HistogramView`, a port of
  RawBoy's, clicking it toggles clipping), `ActionMenu` (left),
  `BrowserStrip` (top: breadcrumb + filmstrip from `ThumbnailStore`). Scrolling goes through `PanelScroll`, because
  `ImageRenderer` (debug snapshots) draws nothing inside a ScrollView.
- `Packages/` (one local Swift package):
  - `RawBoyBrowseKit`: pure Swift, **no AppKit/SwiftUI/CoreGraphics/ImageIO** (own `Point2D`/`Size2D`: Foundation's
    `CGPoint` lacks `.zero` and `Equatable` without CoreGraphics). Design tokens, file types, `PhotoGroups` (port of
    RawBoy Browser's `PhotoGroups.ts`: RAW + JPEG = one photo, the raw is main), `ZoomMath`, `PrefetchPlan`,
    `LRUCache`, `ViewerCommand`, `ByteSource`/`FileSource` (block-cached random reads), `EmbeddedPreviews` and
    `CaptureDate` (ports of RawBoy's `EmbeddedPreview.ts` / `CaptureDate.ts`, with its tests; JPEG XL previews not
    ported: ImageIO decodes those DNGs), `PhotoOrder` (port of RawBoy's), `ExifFormat` (shutter, aperture, bias, codes, camera name), `SharedZoom` (zoom over fit + centre as fractions
    of the photo, so another photo shows the same spot), `Rating` / `FlagFilter` and `XmpSidecar` (ports of
    RawBoy Browser's rating rules and `XmpSidecar.ts`, with its tests; plus `tiff:Orientation`), `Orientation` (EXIF
    1-8 as mirror + quarter turns: compose, inverse), `CropMath` (port of RawBoy's: aspects, drag, handles, turning a
    crop, with its tests), `DevelopEdits` (the geometry of RawBoy's `rawboy:Develop` JSON: rotation, flips, crop;
    every other field kept, defaults left out, numbers tidied to 6 decimals), `Histogram` + `ClipWarning` (ports of RawBoy's
    Histogram and its shader's `clipWarning`: 64 bins, a channel at 255 = highlight, all ≤ 1 = shadow; keep in step), `EdgeZones` (which panels show: dwell, grace, close delay, corners, pins, Tab; time
    passed in, so tested without timers), `BottomBand`, `Rect2D` (y down); later the XMP sidecar, embedded-preview parser, capture dates and the edge-zone state
    machine. It is meant to move into the RawBoy repo and serve RawBoy desktop and the Windows port.
  - `ViewerImaging`: `ImageLoader` (screen-size preview: a raw's embedded JPEG from `EmbeddedPreviews` when
    ≥ 2560 px, else ImageIO's embedded one, else decoded;
    full resolution for 1:1; `displayReady` redraws to 8-bit BGRA), `ImageStore` (actor: LRU 1.5 GB, shared in-flight
    decodes, sequential prefetch), `PhotoMetadata` (ImageIO properties → the details panel's fields), `Orienting` (apply an `Orientation`,
    checked against ImageIO for all 8; `delta` from the file's own to a sidecar's), `RawDeveloper` (CIRAWFilter as shot, at a scale; raws only: the filter opens PNGs too), `Exporter`
    (JPEG/HEIC, size,
    sidecar rotation, metadata kept, GPS optional, never overwrites), `ImageAnalysis` (histogram from a 512 px
    nearest-neighbour copy, as RawBoy; clip overlay up to 4096 px), `ThumbnailStore` (actor: memory → `DiskThumbnailCache` in ~/Library/Caches/RawBoy Viewer/Thumbnails, keyed by
    path + size + mtime + pixels, 1 GB → made: a raw's embedded JPEG when ≥ 400 px, else ImageIO), `Thumbnailer`.
  - `ViewerFiles`: `FolderWatcher` (FSEvents on the open folder only: structural vs modified names, hidden files
    left out), `FileMoves` (bin with one suffix per photo, Trash, move back), `SidecarFiles` (read; atomic
    writes into every sidecar a photo has; rating from the first one that has it), `FolderScanner` (photos with size, date and `isOnlineOnly`; sidecar names; subfolders without
    packages or `_bin`), `CloudStatus` (ubiquitous status or `SF_DATALESS`). Scanning reads directory entries only,
    never file contents: photo folders are often cloud sync folders where reading a placeholder downloads it. Nothing
    reads an online-only file except opening it in the viewer (and prefetching its direct neighbours).

## Testing

- `swift test --package-path Packages`: unit tests (Swift Testing).
- `xcodebuild -project RawBoyViewer.xcodeproj -scheme RawBoyViewer build`: the app.
- `swift format lint --strict -r App Features Theme Packages/Sources Packages/Tests Packages/Package.swift`: CI runs it;
  `swift format format -i -r …` fixes most of it.
- Real raw test files go in `.raw/` (git-ignored), as in RawBoy.

- `tools/smoke.sh <folder> [steps]`: opens a folder in the debug build through LaunchServices, steps through photos
  (`RAWBOY_AUTOPLAY`), zooms to 1:1, quits, and prints the trace (`RAWBOY_TRACE=1`): load times and presentation options
  (10 = menu bar + Dock hidden), and opens each panel. Given a folder it opens the browser, then the viewer on its
  first photo. `SNAPSHOT=<folder>` also draws each panel into
  `<folder>/panel-*.png` (`ImageRenderer`; thumbnails stay empty, they load later) so panels can be looked at without
  screen recording; with clipping on, the overlay too (`clip-overlay.png`); the browser too (`browser.png`, 1280 × 820), and the first four grid cells with their real
  thumbnails (`cells.png`: the grid's own thumbnails load too late for a snapshot). Test folders: `~/_claude/photos` (Pixel DNG + JPEG), `../RawBoy/.raw` (Sony JXL DNGs).

## Traps found

- **Presentation options need the key window, and the key window needs an active app.** Launched straight from a shell
  the app isn't activated (cooperative activation, macOS 14+) and the menu bar/Dock stay; through LaunchServices
  (`open`, Finder) it works. Hence `NSApp.activate()` in `present()` and `open` in `tools/smoke.sh`.
- **Raw previews come back from ImageIO as 16-bit Display P3**; handing those to a `CALayer` cost ~100 ms on the main
  thread per photo. `ImageLoader.displayReady` converts every image to 8-bit BGRA (premultiplied first, 32 little) in its
  own colour space off the main thread. Setting `contents` still costs 0-50 ms in the commit; IOSurface-backed contents
  might remove that but must be checked for colour by eye first.
- Previews are sized to the screen's long edge in pixels, set on the store in the same task as the first load: a
  separate task could clear the cache after prefetching had begun.

- **The browser window steals the key window from a viewer opened at launch** (SwiftUI shows it after
  `applicationDidFinishLaunching`), and with it go the hidden menu bar and Dock. `AppDelegate` waits for it first.
- Checking UI states in snapshots that need preferences: `defaults export app.rawboy.viewer <file>` first, then
  `defaults import` it back **and** `defaults delete` every key you added (import doesn't remove them). The owner's
  own last folder and recent folders live there.
- **Cameras' EXIF thumbnails are 160 × 120, letterboxed for portrait photos.** ImageIO's
  `CreateThumbnailFromImageIfAbsent` returns them as they are, so `Thumbnailer.fits` (size and aspect) decides
  whether an embedded thumbnail may be used. The disk cache key has a version (`v2|`) to drop thumbnails made the
  wrong way: bump it when how thumbnails are made changes.
- Cells stack picture and badges with `.bottomTrailing` alignment: the picture needs its own
  `.frame(maxWidth: .infinity, maxHeight: .infinity)` or portrait thumbnails sit against the right edge.
- A horizontal SwiftUI `ScrollView` ignores a mouse wheel's vertical turn: `ViewerWindowController.filmstripWheel`
  rewrites wheel events over the filmstrip into horizontal ones (axis 1 → axis 2) in a local event monitor.
- `ImageRenderer` draws native text fields as a yellow placeholder: not a bug in the view.
- `RAWBOY_SAMPLES=<folder> swift test --package-path Packages --filter SampleFiles` runs the parsers over real raws.
  Phone DNGs have no embedded JPEG, Adobe's JPEG XL DNGs only a 256 px one: both fall back to ImageIO.
- **Never wait for main-actor work in `applicationShouldTerminate` with `.terminateLater`**: AppKit then spins its
  own loop where main-actor tasks don't run, and quitting hung. Pending sidecars are written synchronously there.
- `CULL=1 tools/smoke.sh <folder of copies> 0` rates three photos, prints the sidecars, moves the reject to `_bin` and
  undoes it. It changes files: only ever on copies. Smoke runs also change the app's last folder: back up and restore
  the preferences around them (see above). `M7=1` toggles real preview, runs one slide and drives Compare (choose,
  step, synced zoom, rate, close), printing each state.
- SwiftUI's `Edge` clashes with ours in the app target: ours is `PanelEdge`.
- A horizontal `ScrollView` takes all the height it's offered: give it a height (the browser strip's breadcrumb hid the
  filmstrip this way).

- **Crops go into RawBoy's `rawboy:Develop`, with RawBoy's rotation**: RawBoy measures a crop in its turned frame
  and doesn't read `tiff:Orientation`, so a cropped photo (or one with RawBoy edits) gets `rotation` / `flipHorizontal`
  written too, and RawBoy's turn wins when reading. Straightened photos are left to RawBoy. `CROP=1 tools/smoke.sh`
  checks the sidecar, renders the canvas against a Core Graphics crop and the tool, turns, exports, undoes.
- **A sidecar read can predate a write.** `readSidecars` skips photos changed or written since it started
  (`localChanges` counts both), else a reread put back what the file said before an undo's write.
- **Folder watching sees the app's own work too.** `CullingStore` notes the names it writes or moves
  (`isOwnChange`, 2 s) and never lets a reread overwrite a photo with a write pending (`isBusy`). Foundation's atomic
  writes use a visible temporary file (`NAME.xmp.sb-…`), so `AppModel.folderChanged` only reacts to photos, sidecars
  and folders. `WATCH=1 tools/smoke.sh <copies> 0` checks all of it.
- Rotations never touch the files: `tiff:Orientation` in the sidecar is the photo's whole orientation (as
  Lightroom keeps it), and the image, thumbnail and disk caches are keyed by it.
- The packages build with `-O` even in Debug (`Package.swift`): unoptimised pixel loops made the clipping overlay
  take seconds.

- Updates: Sparkle (SPM). `App/Updater.swift` (Check for Updates…, the Settings switch; Debug builds don't check by
  themselves), feed `appcast.xml` on `main` (GitHub's "latest release" link skips pre-releases, so not a release
  asset), DMGs as release assets. `PUBLISH=1 [PRERELEASE=1] tools/release.sh <version>` does it all.
- `tools/release.sh <version>`: Release archive, Developer ID signing and notarization when `DEVELOPER_ID` /
  `NOTARY_PROFILE` are set (ad hoc otherwise), DMG. See docs/releasing.md.

## Conventions

- Swift 6, strict concurrency, macOS 15+.
- No sandbox (direct download). Signing comes from `Config/RawBoyViewer.xcconfig`: ad hoc, unless the git-ignored
  `Config/Signing.local.xcconfig` names a certificate (the owner's free Personal Team on their Mac). Notarizing needs
  the paid programme: docs/releasing.md.
- MIT licence.
- User-visible changes update `README.md`, and the Help sheet once it exists.
