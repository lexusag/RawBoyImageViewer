import Foundation
import os

/// Timing and state notes for development: in the unified log (subsystem app.rawboy.viewer), and on stdout when the
/// environment has RAWBOY_TRACE=1.
enum Trace {
    private static let logger = Logger(subsystem: "app.rawboy.viewer", category: "viewer")
    private static let toStdout = ProcessInfo.processInfo.environment["RAWBOY_TRACE"] == "1"

    static func log(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        if toStdout {
            print("[trace] \(message)")
            fflush(stdout)
        }
    }
}
