import RawBoyBrowseKit
import SwiftUI

/// Left edge: what can be done with the photo, grouped, with each key next to it. Culling (stars, pick, reject) comes
/// in M5, file actions in M6.
struct ActionMenu: View {
    let model: ViewerModel

    var body: some View {
        PanelCard(title: "Actions", edge: .left, model: model) {
            PanelScroll {
                VStack(alignment: .leading, spacing: 2) {
                    PanelSection(title: "Cull").padding(.horizontal, DesignTokens.Spacing.sm)
                    RatingControl(
                        rating: model.rating, onStars: { model.send(.setStars($0)) },
                        onFlag: { model.send(.toggleFlag($0)) }
                    )
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, 4)
                    ActionRow(icon: "flag.slash", title: "Unflag", key: "U") { model.send(.unflag) }
                    ActionRow(
                        icon: model.culling.autoAdvance ? "checkmark.square" : "square",
                        title: "Next photo after rating", key: nil
                    ) { model.culling.autoAdvance.toggle() }
                    ActionRow(icon: "arrow.uturn.backward", title: "Undo", key: "⌘Z") { model.send(.undo) }
                        .disabled(!model.culling.canUndo)

                    PanelSection(title: "View").padding(.horizontal, DesignTokens.Spacing.sm)
                    ActionRow(
                        icon: model.isFit ? "plus.magnifyingglass" : "arrow.down.right.and.arrow.up.left",
                        title: model.isFit ? "Zoom to 1:1" : "Fit to screen", key: "Z"
                    ) { model.send(.toggleZoom) }
                    ActionRow(
                        icon: model.isScreenFilling ? "macwindow" : "rectangle.inset.filled",
                        title: model.isScreenFilling ? "Show in a window" : "Fill the screen", key: "F"
                    ) { model.send(.toggleFullScreen) }
                    ActionRow(
                        icon: "exclamationmark.triangle",
                        title: model.showClipping ? "Hide clipping" : "Show clipping", key: "J"
                    ) { model.send(.toggleClipping) }
                    ActionRow(
                        icon: model.realPreview ? "checkmark.square" : "square", title: "Develop raws (real preview)",
                        key: "R"
                    ) { model.send(.toggleRealPreview) }
                    ActionRow(
                        icon: "play.rectangle", title: model.isSlideshow ? "Stop slideshow" : "Slideshow", key: "S"
                    ) {
                        model.send(.toggleSlideshow)
                    }
                    ActionRow(icon: "rectangle.split.2x1", title: "Compare with the next", key: "C") {
                        model.send(.compare)
                    }
                    ActionRow(icon: "eye.slash", title: "Hide panels", key: "Tab") { model.send(.toggleChrome) }

                    PanelSection(title: "Go to").padding(.horizontal, DesignTokens.Spacing.sm)
                    ActionRow(icon: "backward.end", title: "First photo", key: "Home") { model.send(.first) }
                    ActionRow(icon: "forward.end", title: "Last photo", key: "End") { model.send(.last) }

                    PanelSection(title: "Edit elsewhere").padding(.horizontal, DesignTokens.Spacing.sm)
                    ActionRow(icon: "slider.horizontal.3", title: "Open in \(model.editor.name)", key: "E") {
                        model.send(.openInEditor)
                    }
                    PanelSection(title: "Transform").padding(.horizontal, DesignTokens.Spacing.sm)
                    ActionRow(icon: "rotate.left", title: "Rotate left", key: "[") {
                        model.send(.rotate(clockwise: false))
                    }
                    ActionRow(icon: "rotate.right", title: "Rotate right", key: "]") {
                        model.send(.rotate(clockwise: true))
                    }
                    ActionRow(icon: "crop", title: "Crop…", key: "K") { model.send(.crop) }

                    PanelSection(title: "Output").padding(.horizontal, DesignTokens.Spacing.sm)
                    ActionRow(icon: "square.and.arrow.up.on.square", title: "Export…", key: "⇧⌘E") {
                        model.send(.file(.export))
                    }
                    ActionRow(icon: "doc.on.doc", title: "Copy photo", key: "⌥⌘C") { model.send(.file(.clipboard)) }
                    ActionRow(icon: "square.and.arrow.up", title: "Share…", key: nil) { model.send(.file(.share)) }

                    PanelSection(title: "Files").padding(.horizontal, DesignTokens.Spacing.sm)
                    ActionRow(icon: "folder.badge.plus", title: "Copy to folder…", key: nil) {
                        model.send(.file(.copyTo))
                    }
                    ActionRow(icon: "arrow.right.doc.on.clipboard", title: "Move to folder…", key: nil) {
                        model.send(.file(.moveTo))
                    }
                    ActionRow(icon: "folder", title: "Show in Finder", key: nil) { model.send(.revealFile) }
                    ActionRow(icon: "trash", title: "Move to Trash", key: "⌘⌫") { model.send(.moveToTrash) }

                    PanelSection(title: "Viewer").padding(.horizontal, DesignTokens.Spacing.sm)
                    ActionRow(icon: "xmark", title: "Close the viewer", key: "Esc") { model.send(.close) }
                }
                .padding(DesignTokens.Spacing.sm)
            }
        }
    }
}

/// One action: icon, title and key. Rows are 36 pt high, big enough to hit without aiming.
struct ActionRow: View {
    let icon: String
    let title: String
    let key: String?
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.sm + 4) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .frame(width: 22)
                    .foregroundStyle(Theme.paperWhite)
                Text(title)
                    .font(Theme.body)
                    .foregroundStyle(Theme.paperWhite)
                Spacer(minLength: DesignTokens.Spacing.sm)
                if let key {
                    Text(key)
                        .font(.system(size: DesignTokens.FontSize.label, design: .rounded))
                        .foregroundStyle(Theme.ashMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.chip).strokeBorder(Theme.hairline))
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .frame(minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    .fill(hovered ? Theme.graphiteRaised : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
