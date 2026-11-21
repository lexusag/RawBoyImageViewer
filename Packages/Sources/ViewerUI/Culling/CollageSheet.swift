import AppKit
import Observation
import RawBoyBrowseKit
import SwiftUI
import ViewerImaging

/// The collage being made: the chosen photos' previews and their layout, with what the sheet's buttons do.
@MainActor
@Observable
final class CollageModel {
    let folder: URL
    let destination: URL
    let orientations: [String: Int]
    private let ids: [String]
    var layout = CollageLayout(canvas: CollageCanvas.presets[0].canvas)
    var images: [String: CGImage] = [:]
    var selected: String?
    private(set) var loading = true
    private(set) var exporting = false
    var error: String?
    @ObservationIgnored private var aspects: [String: Double] = [:]

    init(ids: [String], folder: URL, orientations: [String: Int], destination: URL) {
        self.ids = ids
        self.folder = folder
        self.orientations = orientations
        self.destination = destination
    }

    /// Reads the previews, then tiles them.
    func load() async {
        let folder = folder
        for id in ids {
            let url = folder.appendingPathComponent(id)
            let orientation = orientations[id]
            let loaded = await Task.detached(priority: .userInitiated) {
                ImageLoader.preview(of: url, maxPixelSize: 1400, orientation: orientation)
            }.value
            guard let loaded, loaded.fullSize.height > 0 else { continue }
            images[id] = loaded.cgImage
            aspects[id] = loaded.fullSize.width / loaded.fullSize.height
        }
        arrange()
        loading = false
    }

    /// Tiles the photos again (what the sheet starts from), keeping size, gap and colour.
    func arrange() {
        let present = ids.filter { images[$0] != nil }
        let background = layout.background
        layout = .arranged(
            ids: present, aspects: present.map { aspects[$0] ?? 1 }, canvas: layout.canvas, gap: layout.gap)
        layout.background = background
        selected = nil
    }

    func remove(_ id: String) {
        layout.remove(id)
        if selected == id { selected = nil }
    }

    /// Renders at the canvas size and writes the JPEG; returns its URL, or nil with `error` set.
    func export() async -> URL? {
        guard !exporting, !layout.items.isEmpty else { return nil }
        exporting = true
        defer { exporting = false }
        let layout = layout
        let folder = folder
        let destination = destination
        let orientations = orientations
        let longEdge = min(6000, max(layout.canvas.width, layout.canvas.height))
        do {
            return try await Task.detached(priority: .userInitiated) {
                var full: [String: CGImage] = [:]
                for item in layout.items {
                    let url = folder.appendingPathComponent(item.id)
                    if let loaded = ImageLoader.preview(
                        of: url, maxPixelSize: longEdge, orientation: orientations[item.id])
                    {
                        full[item.id] = loaded.cgImage
                    }
                }
                guard let image = CollageRenderer.render(layout, images: full) else {
                    throw Exporter.ExportError.unwritable("the collage")
                }
                return try CollageRenderer.writeJPEG(image, quality: 0.92, to: destination)
            }.value
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}

/// Makes a collage of the selected photos: drag them, resize them by their handles, pick the output size, the gap and
/// the frame colour, then save a JPEG.
struct CollageSheet: View {
    @Bindable var model: CollageModel
    let onCancel: () -> Void
    let onDone: (URL) -> Void

    private struct Drag {
        let id: String
        let handle: CollageHandle?
        let start: Rect2D
    }

    @State private var drag: Drag?

    private static let swatches: [(String, UInt32)] = [
        ("White", 0xFFFF_FF), ("Paper", DesignTokens.Colour.paperWhite), ("Grey", 0x8080_80),
        ("Ink", DesignTokens.Colour.inkBlack), ("Black", 0x0000_00), ("Amber", DesignTokens.Colour.safelightAmber),
    ]
    private static let custom = "Custom"

    private var sizeChoice: Binding<String> {
        Binding(
            get: { model.layout.canvas.presetName ?? Self.custom },
            set: { name in
                if let preset = CollageCanvas.presets.first(where: { $0.name == name }) {
                    model.layout.retarget(to: preset.canvas)
                }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Collage of \(model.layout.items.count) photos")
                .font(Theme.title)
                .foregroundStyle(Theme.paperWhite)
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                canvasArea
                controls.frame(width: 250)
            }
            HStack {
                Text("Saves to \((model.destination.path as NSString).abbreviatingWithTildeInPath)")
                    .font(Theme.label)
                    .foregroundStyle(Theme.ashMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let error = model.error {
                    Text(error).font(Theme.label).foregroundStyle(Theme.warningRed)
                }
                Button("Cancel", action: onCancel)
                    .buttonStyle(.rawBoy)
                    .keyboardShortcut(.cancelAction)
                Button(model.exporting ? "Saving…" : "Save JPEG") {
                    Task { if let url = await model.export() { onDone(url) } }
                }
                .buttonStyle(.rawBoyPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(model.loading || model.exporting || model.layout.items.isEmpty)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(width: 940, height: 700)
        .background(Theme.graphiteSurface)
        .task { await model.load() }
    }

    // MARK: Canvas

    private var canvasArea: some View {
        GeometryReader { proxy in
            let canvas = model.layout.canvas
            let scale = min(proxy.size.width / Double(canvas.width), proxy.size.height / Double(canvas.height))
            canvasView(scale: scale)
                .frame(width: Double(canvas.width) * scale, height: Double(canvas.height) * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if model.loading { Text("Loading…").font(Theme.body).foregroundStyle(Theme.ashMuted) }
                }
        }
        .padding(DesignTokens.Spacing.sm)
        .background(Theme.inkBlack)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
    }

    private func canvasView(scale: Double) -> some View {
        let layout = model.layout
        let images = model.images
        let selected = model.selected
        return Canvas { context, _ in
            context.fill(
                Path(
                    CGRect(
                        x: 0, y: 0, width: Double(layout.canvas.width) * scale,
                        height: Double(layout.canvas.height) * scale)),
                with: .color(Color(hex: layout.background)))
            for item in layout.items {
                guard let image = images[item.id] else { continue }
                let frame = layout.drawnFrame(item.frame)
                let cover = CollageLayout.coverRect(
                    image: Size2D(width: Double(image.width), height: Double(image.height)), in: frame)
                context.drawLayer { layer in
                    layer.clip(to: Path(Self.rect(frame, scale)))
                    layer.draw(Image(decorative: image, scale: 1), in: Self.rect(cover, scale))
                }
            }
            if let selected, let item = layout.item(selected) {
                let r = Self.rect(item.frame, scale)
                context.stroke(Path(r), with: .color(Theme.amber), lineWidth: 2)
                for handle in CollageHandle.allCases {
                    let p = handle.point(on: item.frame)
                    let dot = CGRect(x: p.x * scale - 5, y: p.y * scale - 5, width: 10, height: 10)
                    context.fill(Path(dot), with: .color(Theme.amber))
                    context.stroke(Path(dot), with: .color(Theme.amberInk), lineWidth: 1)
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in dragChanged(value, scale: scale) }
                .onEnded { _ in drag = nil }
        )
    }

    private static func rect(_ r: Rect2D, _ scale: Double) -> CGRect {
        CGRect(x: r.x * scale, y: r.y * scale, width: r.width * scale, height: r.height * scale)
    }

    private func dragChanged(_ value: DragGesture.Value, scale: Double) {
        guard !model.loading else { return }
        if drag == nil {
            let start = Point2D(x: value.startLocation.x / scale, y: value.startLocation.y / scale)
            switch model.layout.hit(at: start, selected: model.selected, handleRadius: 9 / scale) {
            case .handle(let id, let handle)?:
                if let item = model.layout.item(id) { drag = Drag(id: id, handle: handle, start: item.frame) }
            case .body(let id)?:
                model.selected = id
                model.layout.bringToFront(id)
                if let item = model.layout.item(id) { drag = Drag(id: id, handle: nil, start: item.frame) }
            case nil:
                model.selected = nil
            }
        }
        guard let drag, let index = model.layout.items.firstIndex(where: { $0.id == drag.id }) else { return }
        let dx = value.translation.width / scale
        let dy = value.translation.height / scale
        model.layout.items[index].frame =
            drag.handle.map {
                model.layout.resized(drag.start, handle: $0, dx: dx, dy: dy, excluding: drag.id)
            } ?? model.layout.moved(drag.start, dx: dx, dy: dy, excluding: drag.id)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            group("Size") {
                Menu {
                    ForEach(CollageCanvas.presets, id: \.name) { preset in
                        Button("\(preset.name)  ·  \(preset.canvas.width) × \(preset.canvas.height)") {
                            model.layout.retarget(to: preset.canvas)
                        }
                    }
                } label: {
                    Text(sizeChoice.wrappedValue)
                }
                .menuStyle(.button)
                .buttonStyle(.rawBoy)
                .fixedSize()
                HStack(spacing: DesignTokens.Spacing.xs) {
                    TextField("Width", value: sideBinding(\.width), format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                    Text("×").foregroundStyle(Theme.ashMuted)
                    TextField("Height", value: sideBinding(\.height), format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                    Text("px").font(Theme.label).foregroundStyle(Theme.ashMuted)
                }
            }
            group("Frame colour") {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(Self.swatches, id: \.0) { name, hex in
                        Button {
                            model.layout.background = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle().strokeBorder(
                                        model.layout.background == hex ? Theme.amber : Theme.hairline,
                                        lineWidth: model.layout.background == hex ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                    ColorPicker("Custom colour", selection: backgroundBinding, supportsOpacity: false)
                        .labelsHidden()
                }
            }
            group("Gap  ·  \(Int(model.layout.gap)) px") {
                Slider(value: $model.layout.gap, in: 0...120, step: 2)
                    .tint(Theme.amber)
            }
            group("Photos") {
                Button("Tile again") { model.arrange() }
                    .buttonStyle(.rawBoy)
                    .help("Puts every photo back in an even grid")
                if let id = model.selected {
                    Text(id).font(Theme.label).foregroundStyle(Theme.ashMuted).lineLimit(1).truncationMode(.middle)
                    HStack {
                        Button("Bring to front") { model.layout.bringToFront(id) }.buttonStyle(.rawBoy)
                        Button("Remove") { model.remove(id) }.buttonStyle(.rawBoy)
                    }
                } else {
                    Text(
                        "Drag a photo to move it; select it to resize by its handles. "
                            + "Edges snap to the canvas and to other photos."
                    )
                    .font(Theme.label)
                    .foregroundStyle(Theme.ashMuted)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title.uppercased())
                .font(Theme.label)
                .foregroundStyle(Theme.ashMuted)
            content()
        }
    }

    private func sideBinding(_ side: WritableKeyPath<CollageCanvas, Int>) -> Binding<Int> {
        Binding(
            get: { model.layout.canvas[keyPath: side] },
            set: { value in
                var canvas = model.layout.canvas
                canvas[keyPath: side] = value
                model.layout.retarget(to: CollageCanvas(width: canvas.width, height: canvas.height))
            })
    }

    private var backgroundBinding: Binding<Color> {
        Binding(
            get: { Color(hex: model.layout.background) },
            set: { color in
                guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
                func byte(_ v: CGFloat) -> UInt32 { UInt32((min(1, max(0, v)) * 255).rounded()) }
                model.layout.background =
                    byte(c.redComponent) << 16 | byte(c.greenComponent) << 8 | byte(c.blueComponent)
            })
    }
}

extension AppModel {
    /// The collage sheet for [ids] (the browser's selection, in browser order).
    func showCollage(_ ids: [String], _ folder: URL) {
        guard let parent = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        guard ids.count >= 2 else {
            say("Select two or more photos to make a collage")
            return
        }
        let ids = Array(ids.prefix(12))
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 700), styleMask: [.titled],
            backing: .buffered, defer: false)
        var orientations: [String: Int] = [:]
        for id in ids { if let o = culling.orientation(id) { orientations[id] = o } }
        let model = CollageModel(
            ids: ids, folder: folder, orientations: orientations, destination: Self.exportDestination.url(in: folder))
        let view = CollageSheet(
            model: model,
            onCancel: { parent.endSheet(sheet) },
            onDone: { [weak self] url in
                parent.endSheet(sheet)
                self?.say("Saved collage \(url.lastPathComponent)")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            })
        sheet.contentViewController = NSHostingController(rootView: view.preferredColorScheme(.dark))
        parent.beginSheet(sheet)
    }
}
