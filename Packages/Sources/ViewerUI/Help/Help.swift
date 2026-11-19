import AppKit
import RawBoyBrowseKit
import SwiftUI

/// Every key and gesture, by place (RawBoy's "?" sheet, here ⌘/ or ?). Keep it in step with the controls, and with
/// README.md's tables.
enum HelpContent {
    struct Item: Identifiable {
        let keys: String
        let text: String
        var id: String { keys + text }
    }

    struct Section: Identifiable {
        let title: String
        let items: [Item]
        var id: String { title }
    }

    static let sections: [Section] = [
        Section(
            title: "Browser",
            items: [
                Item(keys: "Click · ⌘-click · ⇧-click", text: "Select one, add one, select a range"),
                Item(keys: "Drag on empty space", text: "Select what the rectangle touches (⇧ adds, ⌘ toggles)"),
                Item(keys: "Arrows", text: "Move"),
                Item(keys: "Double-click · Return · Space", text: "Open the viewer (or a folder tile)"),
                Item(keys: "⌘A · Esc", text: "Select all · clear"),
                Item(keys: "⌘C · ⌘V", text: "Copy the selection · paste files here (Finder's too)"),
                Item(keys: "⌘F", text: "Search names"),
                Item(keys: "⌘↑ · ⌫", text: "Up a folder"),
                Item(keys: "⌘R", text: "Reload the folder"),
                Item(keys: "C", text: "Compare the selection (2–4; one photo with the next)"),
                Item(keys: "S", text: "Slideshow from the selection"),
                Item(keys: "Drag photos", text: "Out to Finder or another app, or onto a folder in the sidebar"),
                Item(keys: "Drop files or a folder", text: "On the browser: opens the folder, or the photo's folder"),
                Item(keys: "Right-click", text: "Everything for the photo or the selection"),
            ]),
        Section(
            title: "Rating (browser and viewer)",
            items: [
                Item(keys: "1 – 5 · 0", text: "Stars (the same number again clears them) · no stars"),
                Item(keys: "P · X · U", text: "Pick · Reject (the same key again unflags) · Unflag"),
                Item(
                    keys: "⌘Z",
                    text: "Undo the last rating, rotation, rename, new folder, or move to _bin, a folder or the Trash"),
                Item(keys: "[ · ]", text: "Rotate left · right (kept in the sidecar; the file isn't changed)"),
                Item(
                    keys: "⌘⌫ · ⌦",
                    text: "Ask, then move to the Trash: photos with JPEG and sidecars, folders (⌦ is Fn-⌫ on a laptop)"),
                Item(
                    keys: "F2",
                    text:
                        "Rename the selection with one template: {name} {date} {time} {camera} {lens} {iso} {folder}, "
                        + "# counters (### = 001), plus find and replace (text or regex, $1 for groups); the JPEG and sidecars "
                        + "follow, ⌘Z undoes"),
                Item(keys: "⇧⌘E · ⌥⌘C", text: "Export · Copy the photo"),
            ]),
        Section(
            title: "Viewer",
            items: [
                Item(keys: "→ ↓ Space · ← ↑ ⌫", text: "Next · previous photo"),
                Item(keys: "Bottom of the photo", text: "Left half previous, right half next; hold to keep going"),
                Item(keys: "Wheel · two-finger swipe", text: "Previous / next while the photo fits"),
                Item(keys: "⌘C", text: "Copy the picture on screen as an image (⌥⌘C copies the file)"),
                Item(keys: "Z", text: "Fit ↔ 1:1 at the pointer"),
                Item(keys: "Double-click", text: "Back to the browser"),
                Item(keys: "Right-click", text: "Send to RawBoy Pro or Auto, and the photo's actions"),
                Item(keys: "Press and hold", text: "1:1 while held; drag to look around"),
                Item(keys: "Pinch · wheel (zoomed in)", text: "Zoom; drag or scroll to pan"),
                Item(
                    keys: "K",
                    text:
                        "Crop (kept in the sidecar the way RawBoy keeps it; Return applies, Esc cancels; "
                        + "Save copy writes NAME_crop beside the photo, Save as… lets you choose)"),
                Item(keys: "R", text: "Raws developed by macOS instead of the camera's JPEG"),
                Item(keys: "J", text: "Show clipped highlights red, crushed shadows blue"),
                Item(keys: "S", text: "Slideshow (S or Esc stops)"),
                Item(keys: "C", text: "Compare with the next photo"),
                Item(keys: "F", text: "Screen-filling ↔ window"),
                Item(
                    keys: "⇧⌘A",
                    text: "Send the selection (or this photo) to RawBoy Auto, as Looks, Film or As is"),
                Item(keys: "E", text: "Open in RawBoy Desktop (else darktable or the editor in Settings)"),
                Item(keys: "Esc · G · Return", text: "Close the panels, then back to the browser"),
            ]),
        Section(
            title: "Edges of the viewer",
            items: [
                Item(keys: "Left edge · M", text: "Actions"),
                Item(keys: "Right edge · I", text: "Details: histogram, EXIF, file"),
                Item(keys: "Top edge · B", text: "The folder's filmstrip (the wheel scrolls it)"),
                Item(keys: "Pin", text: "Keep a panel showing; the photo fits beside it"),
                Item(keys: "Tab", text: "Hide every panel, pinned ones too"),
            ]),
        Section(
            title: "Compare",
            items: [
                Item(keys: "Click", text: "Choose a photo; with two, the next one takes the other place"),
                Item(keys: "← →", text: "Two photos: step the other one through the folder; more: move the choice"),
                Item(keys: "Zoom · pan · hold", text: "All photos together"),
                Item(keys: "Esc · G · Return", text: "Back to the browser on the chosen photo"),
            ]),
    ]
}

struct HelpView: View {
    var body: some View {
        PanelScroll {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                // The version first: what people look for in Help when they report something.
                Text(ViewerHost.versionLine)
                    .font(Theme.label)
                    .foregroundStyle(Theme.ashMuted)
                    .textSelection(.enabled)
                    .accessibilityLabel("Version: \(ViewerHost.versionLine)")
                Text("Keys and gestures")
                    .font(Theme.display)
                    .foregroundStyle(Theme.paperWhite)
                Text("Letters work by key position, so they work on any keyboard layout.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.ashMuted)
                ForEach(HelpContent.sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        PanelSection(title: section.title)
                        ForEach(section.items) { item in
                            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
                                Text(item.keys)
                                    .font(.system(size: DesignTokens.FontSize.label, design: .rounded).weight(.medium))
                                    .foregroundStyle(Theme.paperWhite)
                                    .frame(width: 190, alignment: .leading)
                                Text(item.text)
                                    .font(Theme.body)
                                    .foregroundStyle(Theme.ashMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.xl)
        }
        .frame(minWidth: 560, minHeight: 480)
        .background(Theme.graphiteSurface)
    }
}

/// The help panel: floating, so it shows over the screen-filling viewer too.
@MainActor
public enum HelpWindow {
    private static var panel: NSPanel?

    static func isHelp(_ window: NSWindow) -> Bool { window === panel }

    public static func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            return
        }
        let panel =
            panel
            ?? {
                let p = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
                    styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
                p.title = "RawBoy Viewer Help"
                p.isFloatingPanel = true
                p.level = .floating
                p.hidesOnDeactivate = true
                p.contentViewController = NSHostingController(rootView: HelpView().preferredColorScheme(.dark))
                p.center()
                return p
            }()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }
}
