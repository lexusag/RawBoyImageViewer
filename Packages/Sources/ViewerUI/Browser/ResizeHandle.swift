import AppKit
import SwiftUI

/// A hairline between two panes (or two list columns) that is dragged to resize one of them. [growsRight]: dragging
/// right makes the bound width larger (the pane is on the line's left); otherwise it makes it smaller.
struct ResizeHandle: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    let growsRight: Bool
    @State private var startWidth: Double?
    @State private var hovered = false

    var body: some View {
        Rectangle()
            .fill(hovered || startWidth != nil ? Theme.amber : Theme.hairline)
            .frame(width: 1)
            .overlay(
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        guard inside != hovered else { return }
                        hovered = inside
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { drag in
                                let start = startWidth ?? min(max(width, range.lowerBound), range.upperBound)
                                startWidth = start
                                let delta = growsRight ? drag.translation.width : -drag.translation.width
                                width = min(max(start + delta, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in startWidth = nil }
                    )
            )
            .onDisappear {
                if hovered { NSCursor.pop() }
                hovered = false
            }
    }
}
