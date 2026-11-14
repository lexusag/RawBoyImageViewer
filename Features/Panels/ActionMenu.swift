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
                    ActionRow(icon: "eye.slash", title: "Hide panels", key: "Tab") { model.send(.toggleChrome) }

                    PanelSection(title: "Go to").padding(.horizontal, DesignTokens.Spacing.sm)
                    ActionRow(icon: "backward.end", title: "First photo", key: "Home") { model.send(.first) }
                    ActionRow(icon: "forward.end", title: "Last photo", key: "End") { model.send(.last) }

                    PanelSection(title: "File").padding(.horizontal, DesignTokens.Spacing.sm)
                    ActionRow(icon: "slider.horizontal.3", title: "Open in \(model.editor.name)", key: "E") {
                        model.send(.openInEditor)
                    }
                    ActionRow(icon: "folder", title: "Show in Finder", key: nil) { model.send(.revealFile) }

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
