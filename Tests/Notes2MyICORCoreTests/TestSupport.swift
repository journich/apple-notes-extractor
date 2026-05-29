import Foundation
@testable import Notes2MyICORCore

final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Notes2MyICORTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

final class OutputRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutChunks: [String] = []
    private var stderrChunks: [String] = []

    var stdout: String {
        lock.withLock { stdoutChunks.joined(separator: "\n") }
    }

    var stderr: String {
        lock.withLock { stderrChunks.joined(separator: "\n") }
    }

    func output(_ string: String) {
        lock.withLock {
            stdoutChunks.append(string)
        }
    }

    func error(_ string: String) {
        lock.withLock {
            stderrChunks.append(string)
        }
    }
}
