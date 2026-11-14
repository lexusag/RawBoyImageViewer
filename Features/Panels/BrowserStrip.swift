import RawBoyBrowseKit
import SwiftUI
import ViewerImaging

/// Top edge: where the photo is (the folder path, each part opens that folder) and the folder's filmstrip.
struct BrowserStrip: View {
    let model: ViewerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Breadcrumb(model: model)
                Spacer(minLength: DesignTokens.Spacing.sm)
                Text("\(model.index + 1) / \(model.groups.count)")
                    .font(.system(size: DesignTokens.FontSize.label).monospacedDigit())
                    .foregroundStyle(Theme.ashMuted)
                PinButton(edge: .top, model: model)
            }
            .padding(.leading, DesignTokens.Spacing.md)
            .padding(.trailing, DesignTokens.Spacing.sm)
            .frame(height: 22)
            .padding(.vertical, 6)
            Filmstrip(model: model)
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.card).fill(Theme.graphiteSurface))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.card).strokeBorder(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
    }
}

private struct Breadcrumb: View {
    let model: ViewerModel

    var body: some View {
        let parts = Self.parts(of: model.folder)
        PanelScroll(axis: .horizontal) {
            HStack(spacing: 4) {
                ForEach(Array(parts.enumerated()), id: \.offset) { offset, part in
                    if offset > 0 {
                        Image(systemName: "chevron.compact.right")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.ashMuted)
                    }
                    let isLast = offset == parts.count - 1
                    Button(part.name) { model.openFolder(part.url) }
                        .buttonStyle(.plain)
                        .font(isLast ? Theme.body.weight(.semibold) : Theme.body)
                        .foregroundStyle(isLast ? Theme.paperWhite : Theme.ashMuted)
                        .disabled(isLast)
                        .help(isLast ? "" : "Open \(part.name)")
                }
            }
        }
        .defaultScrollAnchor(.trailing)
        .frame(height: 22)
    }

    /// The folder's path from the home folder (or the volume), as names with their folders.
    static func parts(of folder: URL?) -> [(name: String, url: URL)] {
        guard let folder else { return [] }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        var parts: [(String, URL)] = []
        var url = folder.standardizedFileURL
        while url.path != "/" {
            let isHome = url == home
            parts.append((isHome ? "Home" : url.lastPathComponent, url))
            if isHome { break }
            url = url.deletingLastPathComponent()
        }
        return parts.reversed()
    }
}

private struct Filmstrip: View {
    let model: ViewerModel

    var body: some View {
        ScrollViewReader { proxy in
            PanelScroll(axis: .horizontal) {
                LazyHStack(spacing: 6) {
                    ForEach(Array(model.groups.enumerated()), id: \.offset) { offset, group in
                        FilmstripCell(
                            url: model.url(of: group), isRaw: PhotoFileType(fileName: group.main) == .raw,
                            isCurrent: offset == model.index, store: model.thumbnails
                        )
                        .id(offset)
                        .onTapGesture { model.send(.go(to: offset)) }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
            }
            .frame(height: 76)
            .onAppear { proxy.scrollTo(model.index, anchor: .center) }
            .onChange(of: model.index) { _, index in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }
}

private struct FilmstripCell: View {
    let url: URL?
    let isRaw: Bool
    let isCurrent: Bool
    let store: ThumbnailStore
    @State private var image: CGImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.chip).fill(Theme.graphiteRaised)
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(3)
            }
            if isRaw {
                Text("RAW")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.ashMuted)
                    .padding(.horizontal, 3)
                    .background(Theme.graphiteSurface.opacity(0.9))
                    .padding(4)
            }
        }
        .frame(width: 96, height: 72)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.chip)
                .strokeBorder(isCurrent ? Theme.amber : Theme.hairline, lineWidth: isCurrent ? 2 : 1)
        )
        .contentShape(Rectangle())
        .task(id: url) {
            guard let url else { return }
            image = await store.thumbnail(url)?.cgImage
        }
    }
}
