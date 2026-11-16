import AppKit
import Observation
import RawBoyBrowseKit
import SwiftUI
import ViewerImaging

/// One export running in the background: the browser's bar shows how far it has got, and the user can keep working.
@MainActor
@Observable
final class ExportJob {
    enum State: Equatable { case running, finished, cancelled }

    let total: Int
    let destination: URL
    private(set) var done = 0
    private(set) var failed: [String] = []
    private(set) var state = State.running
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored var onChange: (() -> Void)?

    init(total: Int, destination: URL) {
        self.total = total
        self.destination = destination
    }

    var processed: Int { done + failed.count }
    var fraction: Double { total == 0 ? 1 : Double(processed) / Double(total) }
    var isRunning: Bool { state == .running }

    /// One line for the bar when the job is over.
    var summary: String {
        let name = destination.lastPathComponent
        let photos = "\(done) photo\(done == 1 ? "" : "s")"
        switch state {
        case .running: return "Exporting \(processed) of \(total)…"
        case .cancelled: return "Export stopped: \(photos) saved to \(name)"
        case .finished:
            if failed.isEmpty { return "Exported \(photos) to \(name)" }
            let shown = failed.prefix(3).joined(separator: ", ") + (failed.count > 3 ? "…" : "")
            return "Exported \(done); couldn't export \(shown)"
        }
    }

    func start(items: [(URL, Int?, CropRect?)], options: ExportOptions) {
        let destination = destination
        task = Task { [weak self] in
            let created = await Task.detached(priority: .userInitiated) {
                (try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)) != nil
            }.value
            guard created else {
                self?.failed = items.map { $0.0.lastPathComponent }
                self?.finish()
                return
            }
            for (url, orientation, crop) in items {
                if Task.isCancelled { break }
                let ok = await Task.detached(priority: .userInitiated) {
                    (try? Exporter.export(
                        url, orientation: orientation, crop: crop, to: destination, options: options)) != nil
                }.value
                guard let self else { return }
                if ok { done += 1 } else { failed.append(url.lastPathComponent) }
            }
            self?.finish()
        }
    }

    func cancel() {
        guard isRunning else { return }
        task?.cancel()
    }

    private func finish() {
        state = (task?.isCancelled ?? false) ? .cancelled : .finished
        onChange?()
    }

    func reveal() { NSWorkspace.shared.open(destination) }
}

/// The browser bar's export progress: a thin bar with the count and Stop while it runs, then the result with
/// Show in Finder and a dismiss button.
struct ExportProgress: View {
    let job: ExportJob
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            if job.isRunning {
                ProgressView(value: job.fraction)
                    .progressViewStyle(.linear)
                    .tint(Theme.amber)
                    .frame(width: 120)
                Text("Exporting \(job.processed) of \(job.total)")
                    .font(Theme.label.monospacedDigit())
                    .foregroundStyle(Theme.ashMuted)
                Button("Stop") { job.cancel() }
                    .buttonStyle(.rawBoy)
                    .help("Stops after the photo being exported; the ones done stay")
            } else {
                Text(job.summary)
                    .font(Theme.label)
                    .foregroundStyle(job.failed.isEmpty ? Theme.ashMuted : Theme.amber)
                    .lineLimit(1)
                Button("Show in Finder") { job.reveal() }
                    .buttonStyle(.rawBoy)
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.ashMuted)
                    .help("Dismiss")
            }
        }
    }
}
