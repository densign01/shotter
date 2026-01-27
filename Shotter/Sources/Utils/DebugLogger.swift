import Foundation
import Darwin

/// Minimal file-backed debug logger to diagnose unexpected termination/crashes.
enum DebugLogger {
    // Set to false for release builds.
    static var isEnabled: Bool { false }

    private static let logURL = URL(fileURLWithPath: "/tmp/shotter-debug.log")
    private static var crashFD: Int32 = -1

    static func log(_ message: String, function: StaticString = #function) {
        guard isEnabled else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(function): \(message)\n"
        append(line, to: logURL)
    }

    /// Install basic signal handlers so we can differentiate termination from a crash.
    static func installSignalHandlers() {
        guard isEnabled else { return }
        if crashFD == -1 {
            crashFD = open("/tmp/shotter-crash.log", O_CREAT | O_WRONLY | O_APPEND, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        }

        // Best-effort signal coverage for common crash signals.
        signal(SIGABRT, debugSignalHandler)
        signal(SIGSEGV, debugSignalHandler)
        signal(SIGILL, debugSignalHandler)
        signal(SIGTRAP, debugSignalHandler)
        signal(SIGBUS, debugSignalHandler)
    }

    fileprivate static func writeCrashLine(_ line: String) {
        guard crashFD >= 0 else { return }
        line.withCString { ptr in
            _ = Darwin.write(crashFD, ptr, strlen(ptr))
        }
    }

    private static func append(_ line: String, to url: URL) {
        let data = Data(line.utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch {
                    // Swallow errors in debug logging.
                }
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// Global signal handler entry point (must be a free function).
private func debugSignalHandler(_ signal: Int32) -> Void {
    let line = "Shotter received signal \(signal)\n"
    DebugLogger.writeCrashLine(line)
}

