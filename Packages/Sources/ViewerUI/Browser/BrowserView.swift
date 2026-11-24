import AppKit
import RawBoyBrowseKit
import SwiftUI
import ViewerFiles
import ViewerImaging

/// Pane widths for the browser at [totalWidth], clamped so neither the sidebar nor the preview pane
/// can crush the grid or push panes outside the window. Stored preferences are left untouched so
/// widening the window restores them.
struct BrowserLayout: Equatable, Sendable {
    static let sidebarRange: ClosedRange<Double> = 160...480
    static let previewRange: ClosedRange<Double> = 220...760
    static let dividerWidth: Double = 1
    static let minContentWidth: Double = 260
    static let minMainWithoutPreview: Double = 420
    /// Minimum width for the single-row toolbar and rating bar before they wrap onto two rows.
    static let toolbarSingleRowWidth: Double = 920
    static let ratingBarSingleRowWidth: Double = 880

    let sidebarWidth: Double
    let mainWidth: Double
    let previewWidth: Double
    let contentWidth: Double
    let liveSidebarRange: ClosedRange<Double>
    let livePreviewRange: ClosedRange<Double>

    static func resolve(
        totalWidth: Double,
        sidebarWidth desiredSidebar: Double,
        previewWidth desiredPreview: Double,
        showPreview: Bool
    ) -> BrowserLayout {
        let total = max(totalWidth, 0)
        let minMain =
            showPreview
            ? (minContentWidth + dividerWidth + previewRange.lowerBound)
            : minMainWithoutPreview

        let sidebarMin = min(sidebarRange.lowerBound, max(0, total * 0.3))
        let sidebarMax = max(sidebarMin, min(sidebarRange.upperBound, total - dividerWidth - minMain))
        let liveSidebar = sidebarMin...sidebarMax
        let sidebar = min(max(desiredSidebar, liveSidebar.lowerBound), liveSidebar.upperBound)

        let main = max(total - sidebar - dividerWidth, 0)

        guard showPreview else {
            return BrowserLayout(
                sidebarWidth: sidebar,
                mainWidth: main,
                previewWidth: 0,
                contentWidth: main,
                liveSidebarRange: liveSidebar,
                livePreviewRange: previewRange)
        }

        let previewMin = min(previewRange.lowerBound, max(0, (main - dividerWidth) * 0.5))
        let previewMax = max(previewMin, min(previewRange.upperBound, main - dividerWidth - minContentWidth))
        let livePreview = previewMin...previewMax
        let preview = min(max(desiredPreview, livePreview.lowerBound), livePreview.upperBound)
        let content = max(main - preview - dividerWidth, 0)

        return BrowserLayout(
            sidebarWidth: sidebar,
            mainWidth: main,
            previewWidth: preview,
            contentWidth: content,
            liveSidebarRange: liveSidebar,
            livePreviewRange: livePreview)
    }
}

/// The start screen: places and folders on the left, the folder's photos on the right.
struct BrowserView: View {
    let app: AppModel
    var browser: BrowserModel { app.browser }

    var body: some View {
        GeometryReader { geometry in
            let showsPreview = browser.showPreview && browser.folder != nil
            let layout = BrowserLayout.resolve(
                totalWidth: geometry.size.width,
                sidebarWidth: browser.sidebarWidth,
                previewWidth: browser.previewWidth,
                showPreview: showsPreview)
            HStack(spacing: 0) {
                Sidebar(app: app)
                    .frame(width: layout.sidebarWidth)
                ResizeHandle(
                    width: Bindable(browser).sidebarWidth,
                    range: layout.liveSidebarRange,
                    growsRight: true)
                VStack(spacing: 0) {
                    BrowserToolbar(app: app, availableWidth: layout.mainWidth)
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    HStack(spacing: 0) {
                        content
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                        if showsPreview {
                            ResizeHandle(
                                width: Bindable(browser).previewWidth,
                                range: layout.livePreviewRange,
                                growsRight: false)
                            PreviewPane(app: app)
                                .frame(width: layout.previewWidth)
                        }
                    }
                    if browser.folder != nil, !browser.photos.isEmpty {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        RatingBar(app: app, availableWidth: layout.mainWidth)
                    }
                    if browser.folder != nil, !browser.items.isEmpty {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        SelectionStatus(browser: browser)
                    }
                }
                .frame(width: layout.mainWidth)
                .clipped()
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
        }
        .background(Theme.inkBlack)
        .dropDestination(for: URL.self) { urls, _ in
            app.dropOnBrowser(urls)
        }
    }

    @ViewBuilder private var content: some View {
        if browser.folder == nil {
            EmptyState(
                title: "Open a folder of photos", detail: "Pick one on the left, drop one here, or press ⌘O.",
                action: ("Open…", { app.openFolderPanel() }))
        } else if let error = browser.loadError {
            EmptyState(title: error, detail: nil, action: nil)
        } else if browser.items.isEmpty && browser.filter.isEmpty {
            let count = browser.subfolders.count
            EmptyState(
                title: "No photos here",
                detail: count == 0
                    ? "Folders are on the left." : "It has \(count) subfolder\(count == 1 ? "" : "s").",
                action: count == 0 ? nil : ("Show folders", { browser.showFolders = true }))
        } else if browser.items.isEmpty, browser.isRatingFiltered {
            EmptyState(
                title: "No photos match the rating filter", detail: nil,
                action: (
                    "Show all",
                    {
                        browser.flagFilter = .all
                        browser.minStars = 0
                    }
                ))
        } else if browser.items.isEmpty {
            EmptyState(title: "Nothing matches “\(browser.filter)”", detail: nil, action: nil)
        } else {
            switch browser.viewMode {
            case .grid: PhotoGrid(app: app)
            case .list: PhotoList(app: app)
            }
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
    let availableWidth: Double
    @ViewerSetting(SettingsKeys.uiScale) private var uiScale = 1.0
    @FocusState private var searchFocused: Bool

    var body: some View {
        let browser = app.browser
        let compact = availableWidth < BrowserLayout.toolbarSingleRowWidth
        Group {
            if compact {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        titleBlock(browser)
                        Spacer(minLength: DesignTokens.Spacing.sm)
                        iconButtons(browser)
                    }
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        searchField(browser, flexible: true)
                        Spacer(minLength: DesignTokens.Spacing.sm)
                        sortControl(browser)
                        sizeSlider(browser)
                    }
                }
            } else {
                HStack(spacing: DesignTokens.Spacing.md) {
                    titleBlock(browser)
                    Spacer(minLength: DesignTokens.Spacing.md)
                    iconButtons(browser)
                    searchField(browser, flexible: false)
                    sortControl(browser)
                    sizeSlider(browser)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        // Under the window's traffic lights (and a host's own bar).
        .padding(.top, (34 + app.options.toolbarTopInset) / min(max(uiScale, 0.5), 2))
        .padding(.bottom, 10)
        .titleBarZoom()  // double-click expands the window, as on a title bar
    }

    private func titleBlock(_ browser: BrowserModel) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(browser.folder?.lastPathComponent ?? "RawBoy Viewer")
                .font(Theme.title)
                .foregroundStyle(Theme.paperWhite)
                .lineLimit(1)
            Text(summary(browser))
                .font(Theme.label)
                .foregroundStyle(Theme.ashMuted)
                .lineLimit(1)
        }
    }

    private func iconButtons(_ browser: BrowserModel) -> some View {
        HStack(spacing: 4) {
            ToolbarIcon(icon: "arrow.up", help: "Up a folder (⌘↑)", isOn: false) { browser.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(browser.folder == nil)
            ToolbarIcon(icon: "pencil", help: "Rename the selection (F2)", isOn: false) { app.rename() }
                .disabled(browser.selection.isEmpty)
            ToolbarIcon(icon: "trash", help: "Move the selection to the Trash (⌘⌫, ⌦)", isOn: false) {
                app.moveToTrash()
            }
            .disabled(browser.selection.isEmpty)
            ToolbarIcon(
                icon: browser.showFolders ? "folder.fill" : "folder",
                help: browser.showFolders ? "Hide folders in the grid" : "Show folders in the grid",
                isOn: browser.showFolders
            ) { browser.showFolders.toggle() }
            ToolbarIcon(
                icon: browser.viewMode == .list ? "square.grid.2x2" : "list.bullet",
                help: browser.viewMode == .list ? "Show thumbnails" : "Show a list", isOn: browser.viewMode == .list
            ) { browser.viewMode = browser.viewMode == .list ? .grid : .list }
            ToolbarIcon(
                icon: "sidebar.right",
                help: browser.showPreview ? "Hide the preview" : "Show a preview of the photo",
                isOn: browser.showPreview
            ) { browser.showPreview.toggle() }
            if let folder = browser.folder {
                let favourite = browser.isFavourite(folder)
                ToolbarIcon(
                    icon: favourite ? "star.fill" : "star",
                    help: favourite ? "Remove from Favourites" : "Add to Favourites", isOn: favourite
                ) { browser.toggleFavourite(folder) }
            }
            ToolbarIcon(icon: "questionmark.circle", help: "Keys and gestures (⌘/ or ?)", isOn: false) {
                HelpWindow.toggle()
            }
        }
    }

    private func searchField(_ browser: BrowserModel, flexible: Bool) -> some View {
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
            if !browser.filter.isEmpty {
                Button {
                    browser.filter = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ashMuted)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clear the search")
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 10)
        .frame(
            minWidth: flexible ? 110 : 200,
            idealWidth: 200,
            maxWidth: flexible ? 220 : 200,
            minHeight: 28,
            maxHeight: 28)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.control).fill(Theme.graphiteRaised))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                .strokeBorder(searchFocused ? Theme.amber : Theme.hairline)
        )
        .background(Button("") { searchFocused = true }.keyboardShortcut("f").hidden())
    }

    private func sortControl(_ browser: BrowserModel) -> some View {
        Segmented(
            options: [(PhotoSort.date, "Shoot date"), (PhotoSort.name, "Name")],
            selection: Bindable(browser).sort)
    }

    @ViewBuilder
    private func sizeSlider(_ browser: BrowserModel) -> some View {
        if browser.viewMode == .grid {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3").font(.system(size: 11)).foregroundStyle(Theme.ashMuted)
                Slider(value: Bindable(browser).thumbnailSize, in: 112...320)
                    .frame(width: 96)
                    .tint(Theme.amber)
                Image(systemName: "square.grid.2x2").font(.system(size: 14)).foregroundStyle(Theme.ashMuted)
            }
            .help("Thumbnail size")
        }
    }

    private func summary(_ browser: BrowserModel) -> String {
        guard browser.folder != nil else { return "No folder open" }
        let count = browser.photos.count
        var parts = ["\(count) photo\(count == 1 ? "" : "s")"]
        if browser.showFolders, !browser.subfolders.isEmpty {
            parts.insert("\(browser.subfolders.count) folder\(browser.subfolders.count == 1 ? "" : "s")", at: 0)
        }
        if browser.selection.count > 1 { parts.append("\(browser.selection.count) selected") }
        if browser.isLoading { parts.append("reading dates…") }
        return parts.joined(separator: " · ")
    }
}

/// Under the grid: rate the selection, filter by rating, move rejects to the bin (RawBoy Browser's bar).
/// The always-visible selection counter along the bottom edge.
private struct SelectionStatus: View {
    let browser: BrowserModel

    var body: some View {
        let counts = browser.selectionCounts
        HStack {
            Text(SelectionSummary.text(files: counts.files, folders: counts.folders, bytes: counts.bytes))
                .font(Theme.label)
                .foregroundStyle(Theme.ashMuted)
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(height: 24)
        .background(Theme.graphiteSurface)
    }
}

private struct RatingBar: View {
    let app: AppModel
    let availableWidth: Double

    var body: some View {
        let browser = app.browser
        let culling = app.culling
        let targets = browser.ratingTargets
        let counts = FlagFilter.counts(browser.photos.map { culling.rating($0.id) })
        let shown = targets.count == 1 ? culling.rating(targets[0]) : Rating.none
        let singleRowMin =
            BrowserLayout.ratingBarSingleRowWidth
            + (culling.binCount > 0 ? 80 : 0)
            + (app.exportJob != nil ? 80 : 0)
        let compact = availableWidth < singleRowMin
        Group {
            if compact {
                VStack(spacing: DesignTokens.Spacing.sm) {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        ratingAndStatus(browser: browser, culling: culling, targets: targets, shown: shown)
                        Spacer(minLength: DesignTokens.Spacing.sm)
                        starFilterMenu(browser: browser)
                        binButtons(browser: browser, culling: culling)
                    }
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        flagSegmented(browser: browser, counts: counts)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.sm)
            } else {
                HStack(spacing: DesignTokens.Spacing.md) {
                    ratingAndStatus(browser: browser, culling: culling, targets: targets, shown: shown)
                    Spacer(minLength: DesignTokens.Spacing.sm)
                    flagSegmented(browser: browser, counts: counts)
                    starFilterMenu(browser: browser)
                    binButtons(browser: browser, culling: culling)
                }
                .frame(height: 44)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .background(Theme.graphiteSurface)
        .animation(.easeOut(duration: 0.2), value: culling.message)
        .animation(.easeOut(duration: 0.2), value: app.exportJob?.state)
    }

    @ViewBuilder
    private func ratingAndStatus(
        browser: BrowserModel, culling: CullingStore, targets: [String], shown: Rating
    ) -> some View {
        RatingControl(
            rating: shown, compact: true, onStars: { culling.setStars(browser.ratingTargets, $0) },
            onFlag: { culling.toggleFlag(browser.ratingTargets, $0) }
        )
        .disabled(targets.isEmpty)
        .opacity(targets.isEmpty ? 0.5 : 1)
        if let job = app.exportJob {
            ExportProgress(job: job) { app.exportJob = nil }
        } else if let message = culling.message {
            Text(message)
                .font(Theme.label)
                .foregroundStyle(Theme.ashMuted)
                .lineLimit(1)
                .transition(.opacity)
        }
    }

    private func flagSegmented(browser: BrowserModel, counts: [FlagFilter: Int]) -> some View {
        Segmented(
            options: [
                (FlagFilter.all, "All"), (.picks, "Picks"), (.unflagged, "Unflagged"), (.rejects, "Rejects"),
            ], selection: Bindable(browser).flagFilter, counts: counts)
    }

    private func starFilterMenu(browser: BrowserModel) -> some View {
        Menu {
            ForEach(0...5, id: \.self) { n in
                Button(n == 0 ? "Any stars" : "\(String(repeating: "★", count: n)) or more") {
                    browser.minStars = n
                }
            }
        } label: {
            Text(browser.minStars == 0 ? "Any ★" : "\(browser.minStars)★+")
                .font(Theme.label)
                .foregroundStyle(browser.minStars > 0 ? Theme.amber : Theme.paperWhite)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func binButtons(browser: BrowserModel, culling: CullingStore) -> some View {
        Button("Move rejects to \(FolderScanner.binFolderName)") {
            let order = browser.photos.map(\.group)
            Task { await culling.moveRejectsToBin(order) }
        }
        .buttonStyle(.rawBoy)
        .fixedSize()
        .help("Moves the rejects, their sidecars and JPEGs into the folder's _bin. Nothing is deleted.")
        if culling.binCount > 0 {
            Button("Bin (\(culling.binCount))") { culling.restoreBin() }
                .buttonStyle(.rawBoy)
                .fixedSize()
                .help("Moves everything in _bin back into the folder")
        }
    }
}

/// A toolbar button: an icon, amber when its option is on.
private struct ToolbarIcon: View {
    let icon: String
    let help: String
    let isOn: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(isOn ? Theme.amber : Theme.paperWhite)
                .frame(width: 30, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                        .fill(hovered ? Theme.graphiteRaised : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovered = $0 }
    }
}

/// RawBoy's segmented control: a graphite track, the chosen segment filled amber.
struct Segmented<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    /// A number after a title, always shown (the photos each option would show).
    var counts: [Value: Int] = [:]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                let on = value == selection
                Button {
                    selection = value
                } label: {
                    Text(counts[value].map { "\(title) \($0)" } ?? title)
                        .monospacedDigit()
                        .font(Theme.label.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? Theme.amberInk : Theme.paperWhite)
                        .lineLimit(1)
                        .fixedSize()
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
        .fixedSize()
    }
}
