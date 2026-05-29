import Foundation
import XCTest
@testable import Notes2MyICORCore

final class AppRunnerTests: XCTestCase {
    func testHelpCommandPrintsUsage() {
        let recorder = OutputRecorder()
        let code = AppRunner(output: recorder.output, errorOutput: recorder.error).run(arguments: ["--help"])

        XCTAssertEqual(code, 0)
        XCTAssertTrue(recorder.stdout.contains("Usage:"))
        XCTAssertTrue(recorder.stdout.contains("notes2myicor init"))
    }

    func testVersionCommandPrintsVersion() {
        let recorder = OutputRecorder()
        let code = AppRunner(output: recorder.output, errorOutput: recorder.error).run(arguments: ["version"])

        XCTAssertEqual(code, 0)
        XCTAssertEqual(recorder.stdout.trimmingCharacters(in: .whitespacesAndNewlines), AppVersion.current)
    }

    func testUnknownCommandReturnsUsageError() {
        let recorder = OutputRecorder()
        let code = AppRunner(output: recorder.output, errorOutput: recorder.error).run(arguments: ["unknown"])

        XCTAssertEqual(code, 2)
        XCTAssertTrue(recorder.stderr.contains("Unknown command"))
        XCTAssertTrue(recorder.stderr.contains("Usage:"))
    }

    func testInitCommandCreatesConfigAtRequestedPath() throws {
        let directory = try TemporaryDirectory()
        let configPath = directory.url.appendingPathComponent("nested/config.json")
        let recorder = OutputRecorder()

        let code = AppRunner(output: recorder.output, errorOutput: recorder.error)
            .run(arguments: ["init", "--config", configPath.path])

        XCTAssertEqual(code, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path))
        XCTAssertTrue(recorder.stdout.contains("Created config:"))
    }

    func testInitCommandRefusesToOverwriteWithoutForce() throws {
        let directory = try TemporaryDirectory()
        let configPath = directory.url.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: configPath)

        let recorder = OutputRecorder()
        let code = AppRunner(output: recorder.output, errorOutput: recorder.error)
            .run(arguments: ["init", "--config", configPath.path])

        XCTAssertEqual(code, 1)
        XCTAssertTrue(recorder.stderr.contains("already exists"))
    }
}
