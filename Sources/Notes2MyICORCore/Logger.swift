import Foundation

public enum LogLevel: String, Codable, Sendable {
    case debug
    case info
    case warning
    case error
}

public struct LogEntry: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var level: LogLevel
    public var message: String
    public var metadata: [String: String]

    public init(
        timestamp: Date = Date(),
        level: LogLevel,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.metadata = metadata
    }
}

public struct Logger {
    private let sink: @Sendable (String) throws -> Void
    private let encoder: JSONEncoder
    private let clock: @Sendable () -> Date

    public init(
        sink: @escaping @Sendable (String) throws -> Void,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.sink = sink
        self.clock = clock
    }

    public static func file(url: URL) -> Logger {
        Logger { line in
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = Data((line + "\n").utf8)

            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try data.write(to: url, options: [.atomic])
            }
        }
    }

    public func log(_ level: LogLevel, _ message: String, metadata: [String: String] = [:]) throws {
        let entry = LogEntry(timestamp: clock(), level: level, message: message, metadata: metadata)
        let data = try encoder.encode(entry)
        guard let line = String(data: data, encoding: .utf8) else {
            throw LoggerError.encodingFailed
        }
        try sink(line)
    }
}

public enum LoggerError: Error, Equatable {
    case encodingFailed
}
