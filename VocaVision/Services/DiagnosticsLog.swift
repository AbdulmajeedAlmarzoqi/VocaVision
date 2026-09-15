import Foundation
import Observation
import os

/// In-app diagnostic log: kept in memory for the Diagnostics screen,
/// mirrored to the unified log, and appended to a file in Documents so
/// the user can share it when something goes wrong.
@Observable
@MainActor
final class DiagnosticsLog {
    static let shared = DiagnosticsLog()

    enum Level: String, Sendable {
        case debug = "🔧"
        case info = "ℹ️"
        case notice = "📣"
        case warning = "⚠️"
        case error = "🛑"
    }

    struct Entry: Identifiable, Hashable, Sendable {
        let id = UUID()
        let timestamp: Date
        let category: String
        let level: Level
        let message: String

        var timeString: String {
            timestamp.formatted(Self.timeFormat)
        }

        var formatted: String {
            "\(level.rawValue) \(timeString) [\(category)] \(message)"
        }

        nonisolated static let timeFormat = Date.FormatStyle()
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)
            .second(.twoDigits)
            .secondFraction(.fractional(3))
            .locale(Locale(identifier: "en_US_POSIX"))
    }

    private(set) var entries: [Entry] = []
    private let maxInMemory = 800

    @ObservationIgnored private let writer = LogFileWriter()
    @ObservationIgnored private let osLog = Logger(subsystem: "com.vocavision.app", category: "diag")

    nonisolated var fileURL: URL { writer.fileURL }

    private init() {
        write(category: "boot", level: .info, message: "📋 new session — \(Self.deviceFingerprint())")
    }

    func write(category: String, level: Level, message: String) {
        let entry = Entry(timestamp: Date(), category: category, level: level, message: message)
        entries.append(entry)
        if entries.count > maxInMemory {
            entries.removeFirst(entries.count - maxInMemory)
        }

        let line = entry.formatted
        switch level {
        case .debug: osLog.debug("\(line, privacy: .public)")
        case .info: osLog.info("\(line, privacy: .public)")
        case .notice: osLog.notice("\(line, privacy: .public)")
        case .warning: osLog.warning("\(line, privacy: .public)")
        case .error: osLog.error("\(line, privacy: .public)")
        }
        writer.append(line + "\n")
    }

    func snapshotText() -> String {
        entries.map(\.formatted).joined(separator: "\n")
    }

    func clear() {
        entries.removeAll()
        writer.reset()
        write(category: "boot", level: .info, message: "🧹 log cleared")
    }

    private static func deviceFingerprint() -> String {
        let info = ProcessInfo.processInfo
        return "iOS \(info.operatingSystemVersionString)"
    }
}

/// Serial, off-main file appender. Keeps one handle open per session
/// instead of reopening the file for every line.
nonisolated private final class LogFileWriter: Sendable {
    let fileURL: URL
    private let queue = DispatchQueue(label: "com.vocavision.diag.file", qos: .utility)
    private let handle = OSAllocatedUnfairLock<FileHandle?>(initialState: nil)

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("vocavision-diagnostics.log")
    }

    func append(_ text: String) {
        let url = fileURL
        queue.async { [handle] in
            guard let data = text.data(using: .utf8) else { return }
            let fh: FileHandle? = handle.withLock { current in
                if let current { return current }
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                let opened = try? FileHandle(forWritingTo: url)
                _ = try? opened?.seekToEnd()
                current = opened
                return opened
            }
            try? fh?.write(contentsOf: data)
        }
    }

    func reset() {
        let url = fileURL
        queue.async { [handle] in
            handle.withLock { current in
                try? current?.close()
                current = nil
            }
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// Top-level convenience. Safe from any thread — hops to the main actor.
nonisolated func vlog(_ category: String, _ message: String, level: DiagnosticsLog.Level = .info) {
    if Thread.isMainThread {
        MainActor.assumeIsolated {
            DiagnosticsLog.shared.write(category: category, level: level, message: message)
        }
    } else {
        Task { @MainActor in
            DiagnosticsLog.shared.write(category: category, level: level, message: message)
        }
    }
}
