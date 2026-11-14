import AppKit
import RawBoyBrowseKit
import SwiftUI
import ViewerFiles

/// Recent folders, then places (home folders, cloud storage, volumes) as folder trees that open as they are expanded.
struct Sidebar: View {
    let app: AppModel

    @AppStorage("browser.pinFavourites") private var pinFavourites = true

    /// A row is about 28 pt high; the pinned list stops growing at [pinnedMaxHeight] and scrolls inside itself.
    private static let pinnedMaxHeight = 220.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if pinFavourites {
                let count = max(app.browser.favourites.count, 1)
                PanelScroll { favourites }
                    .frame(height: min(Double(count) * 28 + 44, Self.pinnedMaxHeight + 44))
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.top, 38)
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
            PanelScroll {
                VStack(alignment: .leading, spacing: 2) {
                    if !pinFavourites { favourites }
                    if !app.browser.recent.isEmpty {
                        SidebarHeading(title: "Recent")
                        ForEach(app.browser.recent.prefix(6), id: \.self) { url in
                            FolderRow(
                                url: url, title: url.lastPathComponent, icon: "clock", depth: 0, app: app,
                                tree: false, subtitle: Self.parents(of: url))
                        }
                    }
                    SidebarHeading(title: "Places")
                    ForEach(Self.places(), id: \.url) { place in
                        FolderRow(
                            url: place.url, title: place.title, icon: place.icon, depth: 0, app: app, tree: true,
                            followsCurrent: true)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.top, pinFavourites ? 0 : 38)
                .padding(.bottom, DesignTokens.Spacing.md)
            }
        }
        .background(Theme.graphiteSurface)
    }

    private var favourites: some View {
        VStack(alignment: .leading, spacing: 2) {
            SidebarHeading(title: "Favourites") {
                Button {
                    pinFavourites.toggle()
                } label: {
                    Image(systemName: pinFavourites ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(pinFavourites ? Theme.amber : Theme.ashMuted)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(
                    pinFavourites
                        ? "Favourites stay in view while the rest scrolls: click to unpin" : "Keep favourites in view")
            }
            if app.browser.favourites.isEmpty {
                Text("Star a folder, or right-click one, to keep it here.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.ashMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
            } else {
                ForEach(app.browser.favourites, id: \.self) { url in
                    FolderRow(url: url, title: url.lastPathComponent, icon: "star", depth: 0, app: app, tree: true)
                }
            }
        }
    }

    /// Up to three parent folder names above `url` ("Trip / Day 2 / Edits"), so folders with the same name
    /// (several "_done") can be told apart.
    static func parents(of url: URL) -> String {
        url.deletingLastPathComponent().pathComponents.filter { $0 != "/" }.suffix(3).joined(separator: " / ")
    }

    struct Place {
        let title: String
        let icon: String
        let url: URL
    }

    /// Home folders, cloud sync folders (~/Library/CloudStorage, iCloud Drive) and other volumes, where they exist.
    static func places() -> [Place] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var out: [Place] = [
            Place(title: "Pictures", icon: "photo.on.rectangle", url: home.appendingPathComponent("Pictures")),
            Place(title: "Desktop", icon: "menubar.dock.rectangle", url: home.appendingPathComponent("Desktop")),
            Place(title: "Downloads", icon: "arrow.down.circle", url: home.appendingPathComponent("Downloads")),
            Place(title: "Documents", icon: "doc", url: home.appendingPathComponent("Documents")),
            Place(title: "Home", icon: "house", url: home),
        ]
        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if fm.fileExists(atPath: iCloud.path) { out.append(Place(title: "iCloud Drive", icon: "icloud", url: iCloud)) }
        for url in FolderScanner.subfolders(of: home.appendingPathComponent("Library/CloudStorage")) {
            out.append(Place(title: cloudName(url.lastPathComponent), icon: "cloud", url: url))
        }
        let volumes =
            fm.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        for url in volumes where url.path != "/" {
            out.append(Place(title: url.lastPathComponent, icon: "externaldrive", url: url))
        }
        return out.filter { fm.fileExists(atPath: $0.url.path) }
    }

    /// "GoogleDrive-name@example.com" → "GoogleDrive"; the account isn't shown.
    static func cloudName(_ folder: String) -> String {
        folder.split(separator: "-", maxSplits: 1).first.map(String.init) ?? folder
    }
}

private struct SidebarHeading<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: DesignTokens.FontSize.label, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Theme.ashMuted)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.top, DesignTokens.Spacing.md)
        .padding(.bottom, 4)
    }
}

extension SidebarHeading where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// A folder: click opens it in the grid; the chevron shows its subfolders (read when first expanded).
private struct FolderRow: View {
    let url: URL
    let title: String
    let icon: String
    let depth: Int
    let app: AppModel
    let tree: Bool
    /// Opens itself when the folder shown in the grid is inside it (the Places tree, so a favourite's folder is found).
    var followsCurrent = false
    var subtitle: String = ""
    @State private var expanded = false
    @State private var children: [URL]?
    @State private var hovered = false

    var body: some View {
        let isCurrent = app.browser.folder?.standardizedFileURL == url.standardizedFileURL
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if tree {
                    Button {
                        if children == nil { children = FolderScanner.subfolders(of: url) }
                        expanded.toggle()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.ashMuted)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .frame(width: 14, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(children?.isEmpty == true ? 0 : 1)
                } else {
                    Spacer().frame(width: 14)
                }
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isCurrent ? Theme.amber : Theme.ashMuted)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(Theme.body)
                        .foregroundStyle(isCurrent ? Theme.amber : Theme.paperWhite)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Theme.label)
                            .foregroundStyle(Theme.ashMuted)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, Double(depth) * 14 + 4)
            .padding(.trailing, 6)
            .frame(minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.chip)
                    .fill(isCurrent || hovered ? Theme.graphiteRaised : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture { app.browse(url) }
            .onHover { hovered = $0 }
            .contextMenu { FolderMenu(url: url, browser: app.browser) }
            .help(url.path)
            .onAppear { expandIfCurrentIsInside() }
            .onChange(of: app.browser.folder) { expandIfCurrentIsInside() }

            if expanded, let children {
                ForEach(children, id: \.self) { child in
                    FolderRow(
                        url: child, title: child.lastPathComponent, icon: "folder", depth: depth + 1, app: app,
                        tree: true, followsCurrent: followsCurrent)
                }
            }
        }
    }

    /// Expands towards the folder being shown, never collapsing what the person opened.
    private func expandIfCurrentIsInside() {
        guard followsCurrent, tree, !expanded, let current = app.browser.folder else { return }
        let prefix = url.standardizedFileURL.path
        guard current.standardizedFileURL.path.hasPrefix(prefix == "/" ? prefix : prefix + "/") else { return }
        if children == nil { children = FolderScanner.subfolders(of: url) }
        expanded = true
    }
}
