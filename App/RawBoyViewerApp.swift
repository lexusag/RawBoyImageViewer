import SwiftUI

@main
struct RawBoyViewerApp: App {
    var body: some Scene {
        WindowGroup("RawBoy Viewer") {
            StartView()
                .frame(minWidth: 720, minHeight: 480)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
