import AppKit
import SwiftUI

/// Multi-file drag source for grid tiles and list rows. SwiftUI's `.onDrag` can only place a single item on the
/// pasteboard; starting an AppKit `NSDraggingSession` instead lets Finder, Mail, browsers and other apps receive
/// every selected file and folder at once, while keeping clicks, double-clicks, hover and context menus untouched.
enum FileDrag {
    static let iconSize = NSSize(width: 48, height: 48)

    /// Builds one `NSDraggingItem` per URL so AppKit places every file URL on the dragging pasteboard and renders
    /// icons lazily for the top items in the pile.
    static func draggingItems(for urls: [URL], around point: NSPoint) -> [NSDraggingItem] {
        let size = iconSize
        let frame = NSRect(
            x: point.x - size.width / 2, y: point.y - size.height / 2,
            width: size.width, height: size.height)
        return urls.map { url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.draggingFrame = frame
            item.imageComponentsProvider = {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = size
                let component = NSDraggingImageComponent(key: .icon)
                component.frame = NSRect(origin: .zero, size: size)
                component.contents = icon
                return [component]
            }
            return item
        }
    }
}

extension View {
    @ViewBuilder
    func dragFiles(_ entry: GridEntry, enabled: Bool, app: AppModel) -> some View {
        if enabled { modifier(FileDragModifier(entry: entry, app: app)) } else { self }
    }
}

private struct FileDragModifier: ViewModifier {
    let entry: GridEntry
    let app: AppModel
    @State private var box = DragHostBox()

    func body(content: Content) -> some View {
        content
            .background(DragHostAnchor(box: box))
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { _ in
                        guard let host = box.view, !host.isDragging, let window = host.window,
                            let event = NSApp.currentEvent, event.window === window,
                            event.type == .leftMouseDragged || event.type == .leftMouseDown,
                            !event.modifierFlags.contains(.control)
                        else { return }
                        let urls = app.beginDrag(entry)
                        guard !urls.isEmpty else { return }
                        host.start(urls: urls, event: event) {
                            app.endDrag()
                        }
                    }
            )
    }
}

@MainActor
private final class DragHostBox {
    weak var view: DragHost?
}

private struct DragHostAnchor: NSViewRepresentable {
    let box: DragHostBox

    func makeNSView(context: Context) -> DragHost {
        let view = DragHost()
        box.view = view
        return view
    }

    func updateNSView(_ view: DragHost, context: Context) {
        box.view = view
    }
}

@MainActor
private final class DragHost: NSView, NSDraggingSource {
    private var onEnd: (@MainActor () -> Void)?
    private var activeSession: NSDraggingSession?

    var isDragging: Bool { activeSession != nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func start(urls: [URL], event: NSEvent, onEnd: @escaping @MainActor () -> Void) {
        guard activeSession == nil, !urls.isEmpty, window != nil else { return }
        let items = FileDrag.draggingItems(for: urls, around: convert(event.locationInWindow, from: nil))
        self.onEnd = onEnd
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.draggingFormation = .pile
        activeSession = session
    }

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? [.copy, .move, .generic] : [.copy, .generic]
    }

    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        activeSession = nil
        let done = onEnd
        onEnd = nil
        done?()
    }
}
