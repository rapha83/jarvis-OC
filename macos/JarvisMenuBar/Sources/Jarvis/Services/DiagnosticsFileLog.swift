import Foundation

actor DiagnosticsFileLog {
    static let shared = DiagnosticsFileLog()

    private let maxBytes: UInt64 = 5 * 1024 * 1024
    private let maxBackups = 5
    private static let detailedLoggingKey = "detailedLoggingEnabled"
    private static let sensitiveFields = Set([
        "text",
        "detail",
        "transcript",
        "response",
        "message",
        "path",
        "screenContext",
        "lastTranscription",
        "lastResponse"
    ])

    struct Record: Encodable {
        let ts: String
        let pid: Int32
        let category: String
        let event: String
        let fields: [String: String]
    }

    static var logDirectoryURL: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        return base
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("JARVIS", isDirectory: true)
    }

    static var logURL: URL {
        logDirectoryURL
            .appendingPathComponent("diagnostics.jsonl", isDirectory: false)
    }

    static func ensureLogFileExists() throws -> URL {
        try FileManager.default.createDirectory(
            at: logDirectoryURL,
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        return logURL
    }

    static func exportBundle(report: String) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let exportRoot = logDirectoryURL.appendingPathComponent("Exports", isDirectory: true)
        let exportURL = exportRoot.appendingPathComponent("JARVIS-Diagnostics-\(formatter.string(from: Date()))", isDirectory: true)
        try FileManager.default.createDirectory(at: exportURL, withIntermediateDirectories: true)

        try Data(report.utf8).write(to: exportURL.appendingPathComponent("report.txt"), options: .atomic)
        let currentLog = try ensureLogFileExists()
        try copyIfExists(currentLog, to: exportURL.appendingPathComponent(currentLog.lastPathComponent))
        for index in 1...5 {
            let rotated = currentLog.deletingPathExtension().appendingPathExtension("jsonl.\(index)")
            try copyIfExists(rotated, to: exportURL.appendingPathComponent(rotated.lastPathComponent))
        }
        return exportURL
    }

    private static func copyIfExists(_ source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            return
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    nonisolated func log(category: String, event: String, fields: [String: String] = [:]) {
        let sanitizedFields = Self.sanitize(fields)
        let record = Record(
            ts: ISO8601DateFormatter().string(from: Date()),
            pid: ProcessInfo.processInfo.processIdentifier,
            category: category,
            event: event,
            fields: sanitizedFields
        )
        Task {
            await self.append(record)
        }
    }

    static var isDetailedLoggingEnabled: Bool {
        UserDefaults.standard.object(forKey: detailedLoggingKey) as? Bool ?? true
    }

    private nonisolated static func sanitize(_ fields: [String: String]) -> [String: String] {
        guard !isDetailedLoggingEnabled else {
            return fields
        }
        return fields.reduce(into: [:]) { result, pair in
            let key = pair.key
            if sensitiveFields.contains(key) {
                result[key] = "[redacted]"
            } else {
                let value = pair.value
                result[key] = value.count > 180 ? String(value.prefix(180)) + "..." : value
            }
        }
    }

    private func append(_ record: Record) {
        do {
            let url = Self.logURL
            try FileManager.default.createDirectory(
                at: Self.logDirectoryURL,
                withIntermediateDirectories: true
            )
            try rotateIfNeeded(url: url)

            let data = try JSONEncoder().encode(record) + Data([0x0A])
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Best effort diagnostics; never interrupt the assistant.
        }
    }

    private func rotateIfNeeded(url: URL) throws {
        guard
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attrs[.size] as? NSNumber,
            size.uint64Value > maxBytes
        else {
            return
        }
        let fm = FileManager.default
        let oldest = rotatedURL(base: url, index: maxBackups)
        if fm.fileExists(atPath: oldest.path) {
            try fm.removeItem(at: oldest)
        }
        if maxBackups > 1 {
            for index in stride(from: maxBackups - 1, through: 1, by: -1) {
                let source = rotatedURL(base: url, index: index)
                let destination = rotatedURL(base: url, index: index + 1)
                if fm.fileExists(atPath: source.path) {
                    if fm.fileExists(atPath: destination.path) {
                        try fm.removeItem(at: destination)
                    }
                    try fm.moveItem(at: source, to: destination)
                }
            }
        }
        let first = rotatedURL(base: url, index: 1)
        if fm.fileExists(atPath: first.path) {
            try fm.removeItem(at: first)
        }
        try fm.moveItem(at: url, to: first)
    }

    private func rotatedURL(base: URL, index: Int) -> URL {
        base.deletingPathExtension().appendingPathExtension("jsonl.\(index)")
    }
}

private func + (lhs: Data, rhs: Data) -> Data {
    var data = lhs
    data.append(rhs)
    return data
}
