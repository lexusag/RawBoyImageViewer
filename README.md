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
| 1–5, 0 | Stars on the selection (the same number again clears them); no stars |
| P, X, U | Pick, Reject (the same key again unflags), Unflag |
| ⌘Z | Undo the last rating, move to `_bin` or to the Trash |
| ⌘⌫ | Move to the Trash (with its JPEG and sidecars) |
| [ / ], ⌘[ / ⌘] | Rotate left / right: lossless, kept in the sidecar (`tiff:Orientation`, as Lightroom does) |
| ⇧⌘E | Export as JPEG or HEIC, full size or 3000 / 2048 / 1080 px, location kept or left out |
| ⌥⌘C | Copy the photo (its file) |
| Photo menu, right-click | Copy to / Move to a folder (recent ones remembered; moves undo), Share |
| ⌘↑ | Up a folder |
| C | Compare the selection (2–4 photos; one photo is compared with the next) |
| S | Slideshow from the selection |
| Folder button | Show subfolders as tiles in the grid (off at first) |
| Star button, right-click a folder | Add to / remove from Favourites (top of the sidebar) |

The bar under the grid rates the selection, filters by Picks / Unflagged / Rejects and stars, and moves the rejects
(with their sidecars and JPEGs) into the folder's `_bin` subfolder: nothing is deleted, and **Bin** brings them back.
Ratings are saved as you go in XMP sidecars next to the photos (`NAME.xmp`, or the ones a photo already has), in the
format RawBoy Browser, Lightroom, Capture One and darktable read; other apps' settings in them are left as they are.

**Compare** shows two to four photos side by side, zoomed and panned together. With two, click the better one: the
next photo of the folder takes the other place (← → step through them instead), and the rating keys rate the one
you chose. Esc, G or Return go back to the browser on it.

**Crops** are kept in the sidecar the way RawBoy keeps them (`rawboy:Develop`), with RawBoy's own turn: RawBoy opens
the photo cropped the same way when its "Edits in sidecars" is on. Thumbnails and exports are cropped too.

The open folder is watched: photos added or removed by other apps, and ratings changed in darktable or RawBoy Web,
show up by themselves (⌘R reloads by hand).

Opening a photo from Finder goes straight to the viewer, which fills the screen.

**⌘/ or ?** shows every key. **Settings** (⌘,): open the last folder at launch, what the mouse wheel does, slideshow
speed, real preview, next photo after rating, the external editor, the export folder, the thumbnail cache.

Move the pointer to an edge and rest it there for a moment: the **left** edge shows actions, the **right** edge the
photo's details (its histogram, exposure, camera and lens, file, colour profile, location, credits), the **top** edge the folder's filmstrip (the mouse wheel scrolls it sideways). A panel goes away when the pointer leaves it; its pin keeps
it showing, and the photo then fits beside it. Along the **bottom** of the photo, the left half goes to the previous
photo and the right half to the next (hold to keep going).

| Keys / mouse | |
|---|---|
| → ↓ Space, wheel down, swipe left, bottom right | Next photo |
| ← ↑ ⌫, wheel up, swipe right, bottom left | Previous photo |
| Home / End | First / last photo |
| Z, double-click, smart zoom | Fit ↔ 1:1 at the pointer |
| Press and hold | 1:1 at the pointer while held; drag to look around, release to fit again |
| Pinch, wheel (zoomed in) | Zoom (once zoomed back out to fit, the wheel waits for a pause before changing photos) |
| Drag, two-finger scroll (zoomed in) | Pan |
| F | Screen-filling ↔ window |
| 1–5, 0, P, X, U | Rate, as in the browser; then on to the next photo (Photo › Go to the Next Photo After Rating) |
| ⌘Z, ⌘⌫ | Undo, Move to the Trash |
| [ / ] | Rotate left / right |
| K | Crop: drag corners and edges (RawBoy's aspect ratios), Return applies, Esc cancels |
| R | Raws developed by macOS instead of the camera's embedded JPEG ("real preview"; not RawBoy's look) |
| S | Slideshow from this photo (4 s each, crossfading; S or Esc stops) |
| C | Compare this photo with the next |
| I / M / B | Details / actions / filmstrip panel |
| J, click the histogram | Show clipped highlights red and crushed shadows blue, as RawBoy does |
| Tab | Hide every panel, pinned ones too (again: bring the pinned back) |
| E | Open in darktable (or the photo's default app) |
| Esc | Close the panels; with none showing, back to the browser |
| G, Return | Back to the browser |

A RAW + JPEG pair is one photo, shown from the raw.

Status: early development (see [PLAN.md](PLAN.md)). Windows comes later.

## Releasing

`tools/release.sh <version>` makes a DMG; signing and notarizing need a Developer ID: see
[docs/releasing.md](docs/releasing.md).

## Building

Needs Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen                                  # creates RawBoyViewer.xcodeproj
open RawBoyViewer.xcodeproj               # or build from the command line:
xcodebuild -scheme RawBoyViewer build
swift test --package-path Packages        # unit tests
```

Requires macOS 15 or later.
