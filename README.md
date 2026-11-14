# RawBoy Viewer

A fast photo viewer and culling tool for macOS, from the RawBoy family. The photo fills the screen; the controls wait at its
edges:

- **Right edge:** photo details, EXIF and histogram
- **Left edge:** actions: rate, pick, reject, rotate, export, open elsewhere
- **Top edge:** the folder's filmstrip
- **Bottom of the photo:** previous (left half) and next (right half)

Ratings go into XMP sidecars that RawBoy Browser, Lightroom, Capture One and darktable read. Originals are never changed.

## Using it

Open a folder, or one photo in it (⌘O, drop it on the window, or Finder's Open With). The viewer fills the screen.

Move the pointer to an edge and rest it there for a moment: the **left** edge shows actions, the **right** edge the
photo's details, the **top** edge the folder's filmstrip. A panel goes away when the pointer leaves it; its pin keeps
it showing, and the photo then fits beside it. Along the **bottom** of the photo, the left half goes to the previous
photo and the right half to the next (hold to keep going).

| Keys / mouse | |
|---|---|
| → ↓ Space, wheel down, swipe left, bottom right | Next photo |
| ← ↑ ⌫, wheel up, swipe right, bottom left | Previous photo |
| Home / End | First / last photo |
| Z, double-click, smart zoom | Fit ↔ 1:1 at the pointer |
| Pinch, wheel (zoomed in) | Zoom |
| Drag, two-finger scroll (zoomed in) | Pan |
| F | Screen-filling ↔ window |
| I / M / B | Details / actions / filmstrip panel |
| Tab | Hide every panel, pinned ones too (again: bring the pinned back) |
| E | Open in darktable (or the photo's default app) |
| Esc | Close the panels; with none showing, close the viewer |
| G | Close the viewer |

A RAW + JPEG pair is one photo, shown from the raw.

Status: early development (see [PLAN.md](PLAN.md)). Windows comes later.

## Building

Needs Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen                                  # creates RawBoyViewer.xcodeproj
open RawBoyViewer.xcodeproj               # or build from the command line:
xcodebuild -scheme RawBoyViewer build
swift test --package-path Packages        # unit tests
```

Requires macOS 15 or later.
