import AppKit
import RawBoyBrowseKit
import SwiftUI
import ViewerImaging

/// Right edge: the photo's details. The exposure first, in one line, then the camera, the file and where it was taken.
/// The histogram comes in M4.
struct InfoPanel: View {
    let model: ViewerModel

    var body: some View {
        PanelCard(title: "Details", edge: .right, model: model) {
            PanelScroll {
                VStack(alignment: .leading, spacing: 6) {
                    if let group = model.current {
                        HistogramView(histogram: model.histogram, active: model.showClipping) {
                            model.send(.toggleClipping)
                        }
                        .frame(height: 84)
                        RatingControl(
                            rating: model.rating, onStars: { model.send(.setStars($0)) },
                            onFlag: { model.send(.toggleFlag($0)) }
                        )
                        .padding(.vertical, 4)
                        let m = model.metadata
                        if let summary = m?.exposureSummary {
                            Text(summary)
                                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Theme.paperWhite)
                                .textSelection(.enabled)
                            let extra = [m?.bias, m?.focalLength].compactMap { $0 }
                            if !extra.isEmpty {
                                Text(extra.joined(separator: "  ·  "))
                                    .font(Theme.label)
                                    .foregroundStyle(Theme.ashMuted)
                            }
                        }
                        camera(m)
                        exposure(m)
                        file(group)
                        image(m)
                        location(m)
                        credits(m)
                        PanelSection(title: "Sidecars")
                        let sidecars = model.culling.sidecars[group.main] ?? group.sidecars
                        if sidecars.isEmpty {
                            InfoRow(label: "None yet", value: "A rating creates \(group.stem).xmp next to the photo.")
                        } else {
                            InfoRow(label: "XMP", value: sidecars.joined(separator: "\n"))
                        }
                    }
                }
                .padding(DesignTokens.Spacing.md)
            }
        }
    }

    @ViewBuilder private func camera(_ m: PhotoMetadata?) -> some View {
        if let m, m.camera != nil || m.taken != nil {
            PanelSection(title: "Camera")
            row("Camera", m.camera)
            // Adapted and manual lenses tell the camera nothing.
            InfoRow(label: "Lens", value: m.lens ?? "Not recorded (manual or adapted lens)")
            row("Taken", m.taken?.formatted(date: .abbreviated, time: .standard))
            row("Serial number", m.serialNumber)
        }
    }

    @ViewBuilder private func exposure(_ m: PhotoMetadata?) -> some View {
        if let m, m.shutter ?? m.aperture ?? m.iso ?? m.program ?? m.metering ?? m.flash != nil {
            PanelSection(title: "Exposure")
            row("Shutter", m.shutter)
            row("Aperture", m.aperture)
            row("ISO", m.iso.map { String($0.dropFirst(4)) })
            row("Compensation", m.bias)
            row("Focal length", m.focalLength)
            row("Mode", m.program)
            row("Metering", m.metering)
            row("Flash", m.flash)
            row("White balance", m.whiteBalance)
        }
    }

    @ViewBuilder private func file(_ group: PhotoGroup) -> some View {
        PanelSection(title: "File")
        InfoRow(label: "Name", value: group.main, stacked: true)
        InfoRow(label: "Kind", value: Self.kind(of: group))
        if let folder = model.folder {
            InfoRow(
                label: "Folder", value: (folder.standardizedFileURL.path as NSString).abbreviatingWithTildeInPath,
                stacked: true)
        }
        InfoRow(label: "Position", value: "\(model.index + 1) of \(model.groups.count)")
        row("File size", model.fileSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) })
        row("Modified", model.modified?.formatted(date: .abbreviated, time: .shortened))
    }

    @ViewBuilder private func image(_ m: PhotoMetadata?) -> some View {
        PanelSection(title: "Image")
        row("Size", model.fullSize.map(Self.dimensions))
        row("Colour profile", m?.colourProfile)
        row("Bit depth", m?.bitDepth.map { "\($0) bits per channel" })
    }

    @ViewBuilder private func location(_ m: PhotoMetadata?) -> some View {
        if let m, let coordinates = m.coordinates {
            PanelSection(title: "Location")
            InfoRow(label: "Coordinates", value: coordinates)
            row("Altitude", m.altitude)
            if let lat = m.latitude, let lon = m.longitude,
                let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)&q=\(lat),\(lon)")
            {
                Button("Show in Maps") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.rawBoy)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder private func credits(_ m: PhotoMetadata?) -> some View {
        if let m, m.artist ?? m.copyright ?? m.software != nil {
            PanelSection(title: "Credits")
            row("Artist", m.artist)
            row("Copyright", m.copyright)
            row("Software", m.software)
        }
    }

    @ViewBuilder private func row(_ label: String, _ value: String?) -> some View {
        if let value { InfoRow(label: label, value: value) }
    }

    static func kind(of group: PhotoGroup) -> String {
        func ext(_ name: String) -> String {
            PhotoGroups.stem(of: name) == name
                ? "?" : String(name[name.index(after: name.lastIndex(of: ".")!)...]).uppercased()
        }
        let main = PhotoFileType(fileName: group.main) == .raw ? "RAW (\(ext(group.main)))" : ext(group.main)
        return ([main] + group.companions.map(ext)).joined(separator: " + ")
    }

    static func dimensions(_ size: Size2D) -> String {
        let megapixels = size.width * size.height / 1_000_000
        return
            "\(Int(size.width)) × \(Int(size.height)) px · \(megapixels.formatted(.number.precision(.fractionLength(1)))) MP"
    }
}
