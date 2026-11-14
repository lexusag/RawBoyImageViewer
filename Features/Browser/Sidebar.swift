import AppKit
import RawBoyBrowseKit
import SwiftUI
import ViewerFiles

/// Recent folders, then places (home folders, cloud storage, volumes) as folder trees that open as they are expanded.
struct Sidebar: View {
    let app: AppModel

    var body: some View {
        PanelScroll {
            VStack(alignment: .leading, spacing: 2) {
                if !app.browser.recent.isEmpty {
                    SidebarHeading(title: "Recent")
                    ForEach(app.browser.recent.prefix(6), id: \.self) { url in
                        FolderRow(
                            url: url, title: url.lastPathComponent, icon: "clock", depth: 0, app: app, tree: false)
                    }
                }
                SidebarHeading(title: "Places")
                ForEach(Self.places(), id: \.url) { place in
                    FolderRow(url: place.url, title: place.title, icon: place.icon, depth: 0, app: app, tree: true)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.top, 38)
            .padding(.bottom, DesignTokens.Spacing.md)
        }
        .background(Theme.graphiteSurface)
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

private struct SidebarHeading: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: DesignTokens.FontSize.label, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Theme.ashMuted)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.top, DesignTokens.Spacing.md)
            .padding(.bottom, 4)
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
                Text(title)
                    .font(Theme.body)
                    .foregroundStyle(isCurrent ? Theme.amber : Theme.paperWhite)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.leading, Double(depth) * 14 + 4)
            .padding(.trailing, 6)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.chip)
                    .fill(isCurrent || hovered ? Theme.graphiteRaised : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture { app.browse(url) }
            .onHover { hovered = $0 }
            .help(url.path)

            if expanded, let children {
                ForEach(children, id: \.self) { child in
                    FolderRow(
                        url: child, title: child.lastPathComponent, icon: "folder", depth: depth + 1, app: app,
                        tree: true)
                }
            }
        }
    }
}
