import RawBoyBrowseKit
import SwiftUI

/// Right edge: the photo's details. EXIF and the histogram come in M4.
struct InfoPanel: View {
    let model: ViewerModel

    var body: some View {
        PanelCard(title: "Details", edge: .right, model: model) {
            PanelScroll {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    if let group = model.current {
                        PanelSection(title: "File")
                        InfoRow(label: "Name", value: group.main)
                        InfoRow(label: "Kind", value: Self.kind(of: group))
                        if let folder = model.folder {
                            InfoRow(
                                label: "Folder",
                                value: (folder.standardizedFileURL.path as NSString).abbreviatingWithTildeInPath)
                        }
                        InfoRow(label: "Position", value: "\(model.index + 1) of \(model.groups.count)")
                        if let size = model.fileSize {
                            InfoRow(
                                label: "File size",
                                value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        }
                        if let modified = model.modified {
                            InfoRow(
                                label: "Modified", value: modified.formatted(date: .abbreviated, time: .shortened))
                        }
                        PanelSection(title: "Image")
                        if let size = model.fullSize {
                            InfoRow(label: "Size", value: Self.dimensions(size))
                        }
                        PanelSection(title: "Sidecars")
                        InfoRow(
                            label: group.sidecars.isEmpty ? "None yet" : "XMP",
                            value: group.sidecars.isEmpty
                                ? "Ratings will be saved next to the photo." : group.sidecars.joined(separator: "\n"))
                    }
                }
                .padding(DesignTokens.Spacing.md)
            }
        }
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
