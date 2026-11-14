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
  (Finder "Open With", Dock drops, a path on the command line), `AppModel` (shared state), `Trace` (dev log).
- `Features/Browser/`: the start screen (until the M3 browser). `Theme/`: tokens as SwiftUI/AppKit colours, RawBoy
  button styles.
- `Features/Viewer/`: `ViewerSession` (open folder, photo list from `PhotoGroups`, navigation, load + prefetch through
  `ImageStore`, full resolution on zoom), `ViewerWindowController` (screen-filling borderless window ↔ titled window),
  `ImageCanvasView` (AppKit + one `CALayer`; zoom/pan via `ZoomMath`, mouse/trackpad/keys → `ViewerCommand`),
  `ViewerKeys` (physical key codes).
- `Packages/` (one local Swift package):
  - `RawBoyBrowseKit`: pure Swift, **no AppKit/SwiftUI/CoreGraphics/ImageIO** (own `Point2D`/`Size2D`: Foundation's
    `CGPoint` lacks `.zero` and `Equatable` without CoreGraphics). Design tokens, file types, `PhotoGroups` (port of
    RawBoy Browser's `PhotoGroups.ts`: RAW + JPEG = one photo, the raw is main), `ZoomMath`, `PrefetchPlan`,
    `LRUCache`, `ViewerCommand`; later the XMP sidecar, embedded-preview parser, capture dates and the edge-zone state
    machine. It is meant to move into the RawBoy repo and serve RawBoy desktop and the Windows port.
  - `ViewerImaging`: `ImageLoader` (ImageIO: screen-size preview, embedded one when ≥ 2560 px, else decoded;
    full resolution for 1:1; `displayReady` redraws to 8-bit BGRA), `ImageStore` (actor: LRU 1.5 GB, shared in-flight
    decodes, sequential prefetch), `Thumbnailer`.
  - `ViewerFiles`: folder scanning, file operations. Scanning reads directory entries only, never file contents:
    photo folders are often cloud sync folders where reading a placeholder downloads it.

## Testing

- `swift test --package-path Packages`: unit tests (Swift Testing).
- `xcodebuild -project RawBoyViewer.xcodeproj -scheme RawBoyViewer build`: the app.
- `swift format lint --strict -r App Features Theme Packages/Sources Packages/Tests Packages/Package.swift`: CI runs it;
  `swift format format -i -r …` fixes most of it.
- Real raw test files go in `.raw/` (git-ignored), as in RawBoy.

- `tools/smoke.sh <folder> [steps]`: opens a folder in the debug build through LaunchServices, steps through photos
  (`RAWBOY_AUTOPLAY`), zooms to 1:1, quits, and prints the trace (`RAWBOY_TRACE=1`): load times and presentation options
  (10 = menu bar + Dock hidden). Test folders: `~/_claude/photos` (Pixel DNG + JPEG), `../RawBoy/.raw` (Sony JXL DNGs).

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

## Conventions

- Swift 6, strict concurrency, macOS 15+.
- No sandbox (direct download, notarized later); the app is ad-hoc signed until a Developer ID exists.
- User-visible changes update `README.md`, and the Help sheet once it exists.
