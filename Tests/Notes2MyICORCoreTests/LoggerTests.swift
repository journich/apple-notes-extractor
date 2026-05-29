import Foundation
import XCTest
@testable import Notes2MyICORCore

final class LoggerTests: XCTestCase {
    func testLoggerWritesJSONLines() throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let recorder = LineRecorder()
        let logger = Logger(
            sink: recorder.append,
            clock: { fixedDate }
        )

        try logger.log(.info, "Started", metadata: ["stage": "0"])

        let lines = recorder.lines
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("\"level\":\"info\""))
        XCTAssertTrue(lines[0].contains("\"message\":\"Started\""))
        XCTAssertTrue(lines[0].contains("\"stage\":\"0\""))
    }

    func testFileLoggerCreatesParentDirectoryAndWrites() throws {
        let directory = try TemporaryDirectory()
        let logURL = directory.url.appendingPathComponent("logs/app.log")

        try Logger.file(url: logURL).log(.warning, "Careful")

        let contents = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("\"level\":\"warning\""))
        XCTAssertTrue(contents.contains("\"message\":\"Careful\""))
    }
}

private final class LineRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedLines: [String] = []

    var lines: [String] {
        lock.withLock { recordedLines }
    }

    func append(_ line: String) {
        lock.withLock {
            recordedLines.append(line)
        }
    }
}
