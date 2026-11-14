import AppKit
import RawBoyBrowseKit
import SwiftUI
import ViewerImaging

/// The start screen: places and folders on the left, the folder's photos on the right.
struct BrowserView: View {
    let app: AppModel
    var browser: BrowserModel { app.browser }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(app: app)
                .frame(width: 248)
            Rectangle().fill(Theme.hairline).frame(width: 1)
            VStack(spacing: 0) {
                BrowserToolbar(app: app)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                content
            }
        }
        .background(Theme.inkBlack)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            app.open(url)
            return true
        }
    }

    @ViewBuilder private var content: some View {
        if browser.folder == nil {
            EmptyState(
                title: "Open a folder of photos", detail: "Pick one on the left, drop one here, or press ⌘O.",
                action: ("Open…", { app.openFolderPanel() }))
        } else if let error = browser.loadError {
            EmptyState(title: error, detail: nil, action: nil)
        } else if browser.photos.isEmpty {
            EmptyState(title: "No photos here", detail: "Subfolders are on the left.", action: nil)
        } else if browser.visible.isEmpty {
            EmptyState(title: "Nothing matches “\(browser.filter)”", detail: nil, action: nil)
        } else {
            PhotoGrid(app: app)
        }
    }
}

private struct EmptyState: View {
    let title: String
    let detail: String?
    let action: (String, () -> Void)?

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Text(title).font(Theme.title).foregroundStyle(Theme.paperWhite)
            if let detail { Text(detail).font(Theme.body).foregroundStyle(Theme.ashMuted) }
            if let action { Button(action.0, action: action.1).buttonStyle(.rawBoyPrimary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Spacing.xl)
    }
}

/// The folder's name and count, search, sort and thumbnail size.
private struct BrowserToolbar: View {
    let app: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        let browser = app.browser
        HStack(spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(browser.folder?.lastPathComponent ?? "RawBoy Viewer")
                    .font(Theme.title)
                    .foregroundStyle(Theme.paperWhite)
                    .lineLimit(1)
                Text(summary(browser))
                    .font(Theme.label)
                    .foregroundStyle(Theme.ashMuted)
            }
            Spacer(minLength: DesignTokens.Spacing.md)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.ashMuted)
                TextField("Search names", text: Bindable(browser).filter)
                    .textFieldStyle(.plain)
                    .font(Theme.body)
                    .foregroundStyle(Theme.paperWhite)
                    .focused($searchFocused)
                    .onExitCommand {
                        browser.filter = ""
                        searchFocused = false
                    }
            }
            .padding(.horizontal, 10)
            .frame(width: 200, height: 28)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.control).fill(Theme.graphiteRaised))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    .strokeBorder(searchFocused ? Theme.amber : Theme.hairline)
            )
            .background(Button("") { searchFocused = true }.keyboardShortcut("f").hidden())
            Segmented(
                options: [(PhotoSort.date, "Shoot date"), (PhotoSort.name, "Name")],
                selection: Bindable(browser).sort)
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3").font(.system(size: 11)).foregroundStyle(Theme.ashMuted)
                Slider(value: Bindable(browser).thumbnailSize, in: 112...320)
                    .frame(width: 96)
                    .tint(Theme.amber)
                Image(systemName: "square.grid.2x2").font(.system(size: 14)).foregroundStyle(Theme.ashMuted)
            }
            .help("Thumbnail size")
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.top, 34)  // under the window's traffic lights
        .padding(.bottom, 10)
    }

    private func summary(_ browser: BrowserModel) -> String {
        guard browser.folder != nil else { return "No folder open" }
        let count = browser.photos.count
        var parts = ["\(count) photo\(count == 1 ? "" : "s")"]
        if browser.selection.count > 1 { parts.append("\(browser.selection.count) selected") }
        if browser.isLoading { parts.append("reading dates…") }
        return parts.joined(separator: " · ")
    }
}

/// RawBoy's segmented control: a graphite track, the chosen segment filled amber.
struct Segmented<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                let on = value == selection
                Button {
                    selection = value
                } label: {
                    Text(title)
                        .font(Theme.label.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? Theme.amberInk : Theme.paperWhite)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.segment)
                                .fill(on ? Theme.amber : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.graphiteRaised))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hairline))
    }
}
