import RawBoyBrowseKit
import SwiftUI

/// An edge panel's frame: RawBoy's card (graphite surface, hairline, 12 pt radius, a shadow because it floats) with a
/// title and a pin button. Opaque: nothing translucent or tinted sits over the photo.
struct PanelCard<Content: View>: View {
    let title: String
    let edge: PanelEdge
    let model: ViewerModel
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(title)
                    .font(Theme.title)
                    .foregroundStyle(Theme.paperWhite)
                    .lineLimit(1)
                Spacer(minLength: 0)
                PinButton(edge: edge, model: model)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, 10)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.card).fill(Theme.graphiteSurface))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.card).strokeBorder(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
    }
}

struct PinButton: View {
    let edge: PanelEdge
    let model: ViewerModel

    var body: some View {
        let pinned = model.pinned.contains(edge)
        Button {
            model.send(.togglePin(edge))
        } label: {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(pinned ? Theme.amber : Theme.ashMuted)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pinned ? "Unpin: show only when the pointer is at the edge" : "Pin: keep showing, beside the photo")
        .accessibilityLabel(pinned ? "Unpin panel" : "Pin panel")
    }
}

/// A label and its value, as the info panel lists them: side by side, or the value under the label for long ones.
struct InfoRow: View {
    let label: String
    let value: String
    var stacked = false

    var body: some View {
        if stacked { stackedBody } else { inlineBody }
    }

    private var inlineBody: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
            Text(label)
                .font(Theme.label)
                .foregroundStyle(Theme.ashMuted)
                .frame(width: 104, alignment: .leading)
            Text(value)
                .font(Theme.body)
                .foregroundStyle(Theme.paperWhite)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stackedBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.label)
                .foregroundStyle(Theme.ashMuted)
            Text(value)
                .font(Theme.body)
                .foregroundStyle(Theme.paperWhite)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A section heading inside a panel.
struct PanelSection: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: DesignTokens.FontSize.label, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Theme.ashMuted)
            .padding(.top, DesignTokens.Spacing.sm)
    }
}

extension EnvironmentValues {
    /// Panels drawn by `ImageRenderer` (debug snapshots): it draws nothing inside a ScrollView, so scrolling parts lay
    /// out flat.
    @Entry var isSnapshot = false
}

/// A ScrollView, or its content laid out flat in snapshots.
struct PanelScroll<Content: View>: View {
    var axis: Axis.Set = .vertical
    /// Set where a marquee selection scrolls this view (the browser's grid and list).
    var marquee: Marquee?
    /// Shows the always-visible draggable scroll bar for vertical scroll views without a marquee (such as Places).
    var scrollBar = false
    @ViewBuilder let content: Content
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var position = ScrollPosition()
    @State private var info = MarqueeScrollInfo()

    var body: some View {
        if isSnapshot {
            content.frame(
                maxWidth: .infinity, maxHeight: axis == .vertical ? .infinity : nil, alignment: .topLeading
            ).clipped()
        } else if let marquee {
            ScrollView(axis, showsIndicators: false) { content }.marqueeScrolling(marquee)
                .overlay(alignment: .trailing) {
                    BrowserScrollBar(info: marquee.info) { y in
                        marquee.offset = y
                        marquee.position.scrollTo(y: y)
                    }
                }
        } else if scrollBar && axis == .vertical {
            ScrollView(axis, showsIndicators: false) { content }
                .scrollPosition($position)
                .onScrollGeometryChange(for: MarqueeScrollInfo.self) { geometry in
                    MarqueeScrollInfo(geometry)
                } action: { _, new in
                    info = new
                }
                .overlay(alignment: .trailing) {
                    BrowserScrollBar(info: info) { y in
                        position.scrollTo(y: y)
                    }
                }
        } else {
            ScrollView(axis, showsIndicators: false) { content }
        }
    }
}
