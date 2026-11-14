# RawBoy Viewer

A fast photo viewer and culling tool for macOS, from the RawBoy family. The photo fills the screen; the controls wait at its
edges:

- **Right edge:** photo details, EXIF and histogram
- **Left edge:** actions: rate, pick, reject, rotate, export, open elsewhere
- **Top edge:** the folder's filmstrip
- **Bottom of the photo:** previous (left half) and next (right half)

Ratings go into XMP sidecars that RawBoy Browser, Lightroom, Capture One and darktable read. Originals are never changed.

## Using it

The browser opens on the last folder you looked at. Pick a folder on the left (recent folders, then Pictures, Desktop,
cloud storage and other drives, each opening into its subfolders), drop one on the window, or press ⌘O. Photos show
in the order they were shot (or by name), from the cameras' own previews, so a folder of raws appears in seconds; a
RAW + JPEG pair is one photo. Files that are only in the cloud show a cloud and aren't downloaded until opened.

| In the browser | |
|---|---|
| Click, ⌘-click, Shift-click | Select one, add one, select a range |
| Arrows | Move |
| Double-click, Enter, Space | Open the viewer |
| ⌘A, Esc | Select all, clear |
| ⌘F | Search names |
| ⌘R | Reload the folder |

Opening a photo from Finder goes straight to the viewer, which fills the screen.

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
| Esc | Close the panels; with none showing, back to the browser |
| G | Back to the browser |

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
