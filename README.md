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

| Keys / mouse | |
|---|---|
| → ↓ Space, wheel down, swipe left | Next photo |
| ← ↑ ⌫, wheel up, swipe right | Previous photo |
| Home / End | First / last photo |
| Z, double-click, smart zoom | Fit ↔ 1:1 at the pointer |
| Pinch, wheel (zoomed in) | Zoom |
| Drag, two-finger scroll (zoomed in) | Pan |
| F | Screen-filling ↔ window |
| Esc, G | Close the viewer |

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
