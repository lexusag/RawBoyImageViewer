import AppKit
import RawBoyBrowseKit
import SwiftUI
import ViewerImaging

/// The folder's photos as thumbnails. Click selects, ⌘-click adds, Shift-click selects a range, double-click (or
/// Enter / Space) opens the viewer; arrows move, ⌘A selects all, Esc clears (RawBoy Browser's keys).
struct PhotoGrid: View {
    let app: AppModel
    @FocusState private var focused: Bool
    @State private var columns = 1
    @Environment(\.isSnapshot) private var isSnapshot

    static let spacing = 10.0

    var body: some View {
        let browser = app.browser
        let cell = browser.thumbnailSize
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                PanelScroll {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: cell, maximum: cell), spacing: Self.spacing)],
                        spacing: Self.spacing
                    ) {
                        ForEach(browser.visible) { photo in
                            PhotoCell(
                                photo: photo, size: cell, isSelected: browser.selection.contains(photo.id),
                                store: browser.thumbnails
                            )
                            .id(photo.id)
                            .gesture(
                                TapGesture(count: 2).onEnded { app.openViewer(at: photo.id) }
                                    .exclusively(
                                        before: TapGesture().onEnded {
                                            let flags = NSEvent.modifierFlags
                                            browser.click(
                                                photo.id, command: flags.contains(.command),
                                                shift: flags.contains(.shift))
                                            focused = true
                                        }))
                        }
                    }
                    .padding(DesignTokens.Spacing.md)
                }
                .onChange(of: browser.scrollRequest) {
                    if let anchor = browser.anchor { proxy.scrollTo(anchor) }
                }
                .onAppear {
                    if !isSnapshot, let anchor = browser.anchor { proxy.scrollTo(anchor, anchor: .center) }
                }
            }
            .onAppear { columns = Self.columns(geometry.size.width, cell) }
            .onChange(of: geometry.size.width) { _, width in columns = Self.columns(width, cell) }
            .onChange(of: cell) { _, size in columns = Self.columns(geometry.size.width, size) }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return, .space, .escape]) { press in
            switch press.key {
            case .leftArrow: browser.move(by: -1)
            case .rightArrow: browser.move(by: 1)
            case .upArrow: browser.move(by: -columns)
            case .downArrow: browser.move(by: columns)
            case .escape: browser.clearSelection()
            default:
                if let anchor = browser.anchor { app.openViewer(at: anchor) }
            }
            return .handled
        }
        .onKeyPress(characters: ["a"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            browser.selectAll()
            return .handled
        }
    }

    /// How many cells fit across [width] (the adaptive grid's own arithmetic), for the up/down keys.
    static func columns(_ width: Double, _ cell: Double) -> Int {
        max(Int((width - 2 * DesignTokens.Spacing.md + spacing) / (cell + spacing)), 1)
    }
}

private struct PhotoCell: View {
    let photo: BrowsePhoto
    let size: Double
    let isSelected: Bool
    let store: ThumbnailStore
    @State private var image: CGImage?
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    .fill(isSelected || hovered ? Theme.graphiteRaised : Theme.graphiteSurface)
                if let image {
                    Image(decorative: image, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                } else if photo.isOnlineOnly {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.ashMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .help("Only in the cloud: opening it downloads it")
                }
                HStack(spacing: 3) {
                    if photo.group.sidecars.isEmpty == false { Badge(text: "XMP") }
                    if photo.isRaw { Badge(text: photo.group.companions.isEmpty ? "RAW" : "RAW+") }
                }
                .padding(6)
            }
            .frame(width: size, height: size * 0.75)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    .strokeBorder(isSelected ? Theme.amber : Theme.hairline, lineWidth: isSelected ? 2 : 1))
            Text(photo.name)
                .font(Theme.label)
                .foregroundStyle(isSelected ? Theme.paperWhite : Theme.ashMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: size)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .task(id: photo.id) {
            guard !photo.isOnlineOnly else { return }
            image = await store.thumbnail(photo.url, size: photo.size, modified: photo.modified)?.cgImage
        }
    }
}

private struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.ashMuted)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(Theme.graphiteSurface.opacity(0.92)))
    }
}
