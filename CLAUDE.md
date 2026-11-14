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
- `App/`: the app entry point and scenes. `Features/`: screens (Browser, Viewer, Panels, Compare). `Theme/`: tokens as
  SwiftUI values and the RawBoy button styles.
- `Packages/` (one local Swift package):
  - `RawBoyBrowseKit`: pure Swift, **no AppKit/SwiftUI/ImageIO**. Design tokens, file types, and later the XMP sidecar,
    embedded-preview parser, capture dates, photo groups/order and the edge-zone state machine. It is meant to move into
    the RawBoy repo and serve RawBoy desktop and the Windows port.
  - `ViewerImaging`: ImageIO / Core Image (thumbnails; later decoding, histogram, caches).
  - `ViewerFiles`: folder scanning, file operations. Scanning reads directory entries only, never file contents:
    photo folders are often cloud sync folders where reading a placeholder downloads it.

## Testing

- `swift test --package-path Packages`: unit tests (Swift Testing).
- `xcodebuild -project RawBoyViewer.xcodeproj -scheme RawBoyViewer build`: the app.
- `swift format lint --strict -r App Features Theme Packages/Sources Packages/Tests Packages/Package.swift`: CI runs it;
  `swift format format -i -r …` fixes most of it.
- Real raw test files go in `.raw/` (git-ignored), as in RawBoy.

## Conventions

- Swift 6, strict concurrency, macOS 15+.
- No sandbox (direct download, notarized later); the app is ad-hoc signed until a Developer ID exists.
- User-visible changes update `README.md`, and the Help sheet once it exists.
