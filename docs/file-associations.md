# File type associations

How RawBoy Viewer (`app.rawboy.viewer`) and RawBoy Desktop (`app.rawboy.desktop`) claim files, what Finder does with
those claims, and what happens with both installed. Written 2026-11-16 from the two `Info.plist`s and the handlers in
`App/AppDelegate.swift` (Viewer) and `ios/Desktop/DesktopApp.swift` (Desktop).

## What there is today

| | Viewer | Desktop |
|---|---|---|
| Document types | `public.image`, `public.camera-raw-image`, `com.adobe.raw-image`, `public.folder` | `public.camera-raw-image`, `com.adobe.raw-image`, `public.jpeg`, `public.heic`, `public.heif`, `public.png`, `public.tiff` |
| Role / rank | Viewer / **Alternate** | Editor / **Alternate** |
| Open handler | `application(_:open:)`: the **first** URL only; a folder opens in the browser, a photo opens its folder with that photo selected and the viewer open | `application(_:open:)`: one photo → Pro; several photos or a folder → Auto's batch; `rawboy-desktop://` links → `handle(link:)` |
| URL scheme | none | `rawboy-desktop://auto?as=…&path=…` |

Checked on this Mac (`NSWorkspace.urlsForApplications(toOpen:)`): both apps are listed in Open With for RAF, ARW, DNG,
CR3, NEF, JPEG, HEIC, PNG and TIFF; the Viewer also for WebP and for folders. Neither is the default for anything: XnView,
Affinity and Preview hold those. (The lists show many duplicate entries: every build's copy is registered.)

## Which types

`public.camera-raw-image` is the parent of every camera RAW the system knows (`com.fuji.raw-image` RAF,
`com.sony.arw-raw-image` ARW, `com.canon.cr3-raw-image`, `com.nikon.raw-image` NEF...) and DNG (`com.adobe.raw-image`
conforms to it as well). Launch Services matches by conformance, so declaring the parent covers all of them, including
formats Apple adds later: **no per-extension list is needed**. The plists already do this. What is left to decide is the
rank and the non-RAW types (JPEG, HEIC, PNG, TIFF: Desktop lists them, the Viewer covers them through `public.image`).

A RAW from a camera newer than the macOS version has no UTI yet (`dyn.…`); those open through Open With › Other only.
That is the system's gap, not worth an imported type declaration.

## Ranks, and who wins

Launch Services picks the handler of a type in this order: the user's own choice (Get Info › Open with › Change All, or
`NSWorkspace.setDefaultApplication`), then the declared rank (Owner > Default > Alternate > None), then its own tie-breaks
(newest version, most recently registered). So:

- **Alternate** (both apps now): listed under Open With, never chosen on its own. Safe, and it is why a double-click still
  opens XnView or Preview.
- **Default**: chosen when the user has made no choice and no other app ranks higher. Claiming this for RAW is reasonable
  for the Viewer (opening a RAW to look at it is what it is for); claiming it for JPEG/HEIC/PNG would take over what
  Preview does for people who never chose.
- **Owner** is for types the app defines itself. Neither app defines one.

## Design (proposal; nothing here is changed in the plists yet)

1. **Viewer is the quick-look app; Desktop is the editor.** Viewer: role `Viewer`, rank `Default` for
   `public.camera-raw-image` and `com.adobe.raw-image`, `Alternate` for `public.image` and `public.folder` (so Preview keeps
   JPEG/HEIC, and Finder keeps folders). Desktop: role `Editor`, rank `Alternate` everywhere, so it is in Open With for
   every photo but never takes a double-click away.
2. **With both installed**, a double-click on a RAW opens the Viewer (culling first, as in the workflow), and Open With ›
   RawBoy Desktop (or E in the Viewer, its hand-off to the editor) opens the editor. Neither app tries to
   override the user's explicit choice. With only Desktop installed, nothing claims RAW by default and Open With still
   lists it.
3. **Make default on request, not by force.** A Settings button "Use RawBoy Viewer for RAW photos" calling
   `NSWorkspace.setDefaultApplication(at:toContentType:)` for the types above: macOS asks the user to confirm, so it
   is honest and reversible. Same button in Desktop for users who only have Desktop. No silent claim, no `lsregister`
   tricks.
4. **Open-handler fixes** (small, no plist change): the Viewer takes only the first URL; with several photos selected in
   Finder, Open With should open the folder and select all of them. In Desktop, a Finder open while **Browse** is showing
   switches to Pro; it could stay in Browse and show the photo's folder (when `mode == .browse`), which is what "open this
   in the app I am looking at" means there.
5. **Same bundle ids and separate settings prefixes** stay as they are, so the two apps never clash on `UserDefaults`.

Decision for the owner: step 1's rank change (Viewer `Default` for RAW) is the only one that alters what a double-click
does on a fresh Mac. Everything else is additive. Apps need a re-launch (and sometimes
`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f <app>`)
after a plist change before Finder shows it.
