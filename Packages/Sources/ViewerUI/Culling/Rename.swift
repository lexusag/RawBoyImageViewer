import AppKit
import RawBoyBrowseKit
import SwiftUI
import ViewerFiles
import ViewerImaging

/// A named template and where its numbering starts.
struct RenamePreset: Codable, Equatable, Identifiable {
    var name: String
    var template: String
    var start: Int
    /// Find and replace saved with it (presets saved before it existed have none).
    var replace: RenameReplace?

    var id: String { name }
}

/// Rename for the browser's selection (F2, the Photo menu, the toolbar, right-click): one template for all of them,
/// with keywords and `#` counters as in RawBoy Auto's export names. A photo's JPEG and sidecars are renamed with it.
extension AppModel {
    enum RenameKeys {
        static let template = "rename.template"
        static let start = "rename.start"
        static let presets = "rename.presets"
    }

    static var renamePresets: [RenamePreset] {
        get {
            ViewerSettings.current.data(forKey: RenameKeys.presets)
                .flatMap { try? JSONDecoder().decode([RenamePreset].self, from: $0) } ?? []
        }
        set { ViewerSettings.current.set(try? JSONEncoder().encode(newValue), forKey: RenameKeys.presets) }
    }

    /// Asks how to rename [ids] (default: the browser's selection), then renames them; ⌘Z puts the names back.
    func rename(_ ids: [String]? = nil) {
        if viewerIsKey {
            say("Rename photos from the browser (F2)")
            return
        }
        let ids = ids ?? browser.ratingTargets
        guard !ids.isEmpty, let folder = browser.folder, let parent = NSApp.keyWindow ?? NSApp.mainWindow,
            parent.sheetParent == nil, parent.attachedSheet == nil
        else { return }
        let wanted = Set(ids)
        let photos = browser.visible.filter { wanted.contains($0.id) }.map { photo in
            RenamePhoto(
                group: PhotoGroup(
                    stem: photo.group.stem, main: photo.group.main, companions: photo.group.companions,
                    sidecars: culling.sidecars[photo.id] ?? photo.group.sidecars),
                url: photo.url, date: photo.date, isOnlineOnly: photo.isOnlineOnly)
        }
        guard !photos.isEmpty else { return }
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let defaults = ViewerSettings.current
        // One photo starts from its own name, to type over; several from the last template used.
        let template =
            photos.count == 1
            ? photos[0].group.stem : defaults.string(forKey: RenameKeys.template) ?? "{date}_###"
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560), styleMask: [.titled],
            backing: .buffered, defer: false)
        let view = RenameSheet(
            photos: photos, folderName: folder.lastPathComponent, existing: existing, template: template,
            start: defaults.object(forKey: RenameKeys.start) as? Int ?? 1,
            onCancel: { parent.endSheet(sheet) },
            onRename: { [weak self] items, template, start in
                parent.endSheet(sheet)
                let defaults = ViewerSettings.current
                if items.count > 1 {
                    defaults.set(template, forKey: RenameKeys.template)
                    defaults.set(start, forKey: RenameKeys.start)
                }
                Task { @MainActor in
                    guard let self else { return }
                    let renamed = await self.culling.rename(items)
                    guard !renamed.isEmpty else { return }
                    // The folder was read again; the photos keep their place under their new names.
                    self.browser.selection = Set(renamed.values)
                    self.browser.anchor = items.first.flatMap { renamed[$0.id] } ?? renamed.values.first
                }
            })
        sheet.contentViewController = NSHostingController(rootView: view.preferredColorScheme(.dark))
        parent.beginSheet(sheet)
    }
}

/// What the dialog knows about a photo before reading its metadata.
struct RenamePhoto {
    let group: PhotoGroup
    let url: URL
    let date: String?
    let isOnlineOnly: Bool
}

/// The rename dialog: template, numbering, presets and a live list of old → new names.
struct RenameSheet: View {
    let photos: [RenamePhoto]
    let folderName: String
    let existing: [String]
    @State var template: String
    @State var start: Int
    @State private var replace = RenameReplace()
    @State private var presets = AppModel.renamePresets
    @State private var namingPreset = false
    @State private var presetName = ""
    /// Camera, lens and ISO by photo, read from the files' headers (online-only files are left alone).
    @State private var metadata: [String: PhotoMetadata] = [:]
    @State private var loading = true
    /// One photo: just a name to type, unless the template tools are asked for.
    @State private var macros = false
    @FocusState private var nameFocused: Bool
    let onCancel: () -> Void
    let onRename: ([RenameItem], String, Int) -> Void

    private func context(_ photo: RenamePhoto) -> RenameContext {
        let meta = metadata[photo.group.main]
        let iso = meta?.iso.flatMap { Int($0.filter(\.isNumber)) }
        return RenameContext(
            fileName: photo.group.main, camera: meta?.camera, lens: meta?.lens, iso: iso, date: photo.date,
            folder: folderName)
    }

    /// A single photo, renamed by typing its new name.
    private var plain: Bool { photos.count == 1 && !macros }

    var body: some View {
        let items = RenamePlan.make(
            photos: photos.map { ($0.group, context($0)) }, template: template, start: max(0, start),
            existing: existing, literal: plain, replace: replace)
        let changing = items.filter { $0.status == .ok }
        let conflicts = items.filter { if case .conflict = $0.status { true } else { false } }
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(photos.count == 1 ? "Rename “\(photos[0].group.main)”" : "Rename \(photos.count) photos")
                .font(Theme.title)
                .foregroundStyle(Theme.paperWhite)
            if !plain { presetRow }
            row("Name") {
                HStack(spacing: 4) {
                    TextField("Name", text: $template)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: DesignTokens.FontSize.body, design: .monospaced))
                        .focused($nameFocused)
                    if plain {
                        Text(photoExtension)
                            .font(.system(size: DesignTokens.FontSize.body, design: .monospaced))
                            .foregroundStyle(Theme.ashMuted)
                    }
                }
            }
            findRows
            if photos.count == 1 {
                row("") {
                    Button(macros ? "Just type a name" : "Use keywords and numbers…") { macros.toggle() }
                        .buttonStyle(.rawBoy)
                }
            }
            if photos.count > 1 {
                row("Number from") {
                    HStack {
                        TextField("1", value: $start, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Text("first photo's number, in the order shown")
                            .font(Theme.label)
                            .foregroundStyle(Theme.ashMuted)
                    }
                }
            }
            if !plain {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(RenameTemplate.keywords, id: \.token) { keyword in
                        Button(keyword.token) { template += keyword.token }
                            .buttonStyle(.rawBoy)
                            .help(keyword.text)
                    }
                }
                Text(
                    "# is a counter: # = 1, ## = 01, ### = 001. Click a keyword to add it. The extension stays, and a "
                        + "photo's JPEG and sidecars are renamed with it."
                )
                .font(Theme.label)
                .foregroundStyle(Theme.ashMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
            if !plain || replace.isActive { preview(items) }
            Text(summary(changing: changing.count, conflicts: conflicts))
                .font(Theme.label)
                .foregroundStyle(conflicts.isEmpty ? Theme.ashMuted : Theme.warningRed)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.rawBoy)
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { onRename(items, template, max(0, start)) }
                    .buttonStyle(.rawBoyPrimary)
                    .disabled((loading && !plain) || replace.error != nil || !RenamePlan.canApply(items))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(width: 560)
        .background(Theme.graphiteSurface)
        .task { await readMetadata() }
        .onAppear { nameFocused = true }
    }

    private var currentPresetName: String {
        let match = presets.first { preset in
            preset.template == template && preset.start == start && (preset.replace ?? RenameReplace()) == replace
        }
        return match?.name ?? "None"
    }

    private var presetRow: some View {
        row("Preset") {
            HStack {
                Menu {
                    ForEach(presets) { preset in
                        Button(preset.name) {
                            template = preset.template
                            start = preset.start
                            replace = preset.replace ?? RenameReplace()
                            namingPreset = false
                        }
                    }
                    if !presets.isEmpty { Divider() }
                    Button("Save this name as preset…") { namingPreset = true }
                    if !presets.isEmpty {
                        Menu("Delete preset") {
                            ForEach(presets) { preset in
                                Button(preset.name) {
                                    presets.removeAll { $0.name == preset.name }
                                    AppModel.renamePresets = presets
                                }
                            }
                        }
                    }
                } label: {
                    Text(currentPresetName)
                }
                .menuStyle(.button)
                .buttonStyle(.rawBoy)
                .fixedSize()
                if namingPreset {
                    TextField("Preset name", text: $presetName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit(savePreset)
                    Button("Save", action: savePreset)
                        .buttonStyle(.rawBoy)
                        .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func preview(_ items: [RenameItem]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(items, id: \.id) { item in
                    HStack(spacing: 6) {
                        Text(item.id)
                            .foregroundStyle(Theme.ashMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(Theme.ashMuted)
                        Group {
                            switch item.status {
                            case .ok:
                                Text(item.newMain).foregroundStyle(Theme.paperWhite)
                            case .unchanged:
                                Text("unchanged").foregroundStyle(Theme.ashMuted)
                            case .conflict(let reason):
                                Text(reason).foregroundStyle(Theme.warningRed)
                            }
                        }
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if item.files.count > 1 {
                            Text("+\(item.files.count - 1)")
                                .foregroundStyle(Theme.ashMuted)
                                .help("The JPEG and sidecars renamed with it")
                        }
                    }
                    .font(.system(size: DesignTokens.FontSize.label, design: .monospaced))
                }
            }
            .padding(8)
        }
        .frame(height: 200)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.control).fill(Theme.graphiteRaised))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.control).strokeBorder(Theme.hairline))
    }

    /// Find and replace, applied to the original name or to the name the template gives.
    private var findRows: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            row("Find") {
                TextField("Text to find (optional)", text: $replace.find)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: DesignTokens.FontSize.body, design: .monospaced))
            }
            if replace.isActive {
                row("Replace") {
                    TextField(replace.regex ? "Replacement, $1 for a group" : "Replacement", text: $replace.replace)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: DesignTokens.FontSize.body, design: .monospaced))
                }
                row("") {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        Toggle("Regex", isOn: $replace.regex)
                        Toggle("Match case", isOn: $replace.caseSensitive)
                        if !plain {
                            Picker("In", selection: $replace.target) {
                                Text("Original name").tag(RenameReplace.Target.original)
                                Text("New name").tag(RenameReplace.Target.result)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                    .toggleStyle(.checkbox)
                    .font(Theme.label)
                }
            }
        }
    }

    private func summary(changing: Int, conflicts: [RenameItem]) -> String {
        if let error = replace.error { return error + ": \(replace.find)" }
        if let first = conflicts.first, case .conflict(let reason) = first.status {
            let n = conflicts.count
            return "\(n) photo\(n == 1 ? "" : "s") can't be renamed: \(reason). Nothing is renamed over another file."
        }
        if plain {
            let extra = (photos[0].group.companions.count + photos[0].group.sidecars.count)
            return extra == 0 ? "" : "Its JPEG and sidecars (\(extra)) are renamed with it."
        }
        if loading { return "Reading camera, lens and ISO…" }
        return changing == 0 ? "Nothing would change." : "\(changing) photo\(changing == 1 ? "" : "s") will be renamed."
    }

    /// ".CR2" of the single photo, shown after the name field.
    private var photoExtension: String {
        let main = photos[0].group.main
        return String(main.dropFirst(photos[0].group.stem.count))
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let preset = RenamePreset(
            name: name, template: template, start: start, replace: replace.isActive ? replace : nil)
        if let i = presets.firstIndex(where: { $0.name == name }) {
            presets[i] = preset
        } else {
            presets.append(preset)
        }
        AppModel.renamePresets = presets
        presetName = ""
        namingPreset = false
    }

    private func readMetadata() async {
        let targets = photos.filter { !$0.isOnlineOnly }.map { ($0.group.main, $0.url) }
        let read = await Task.detached(priority: .userInitiated) {
            var out: [String: PhotoMetadata] = [:]
            for (id, url) in targets {
                if let meta = PhotoMetadata.read(url) { out[id] = meta }
            }
            return out
        }.value
        metadata = read
        loading = false
    }

    private func row<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
            Text(label)
                .font(Theme.label)
                .foregroundStyle(Theme.ashMuted)
                .frame(width: 80, alignment: .leading)
            content()
        }
    }
}
