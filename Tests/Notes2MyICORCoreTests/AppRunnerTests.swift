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
        XCTAssertTrue(recorder.stdout.contains("inspect-schema"))
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

    func testInspectSchemaCommandPrintsFixtureSchema() throws {
        let directory = try TemporaryDirectory()
        let databaseURL = directory.url.appendingPathComponent("NoteStore.sqlite")
        try SQLiteFixture.createAppleNotesLikeDatabase(at: databaseURL)

        let recorder = OutputRecorder()
        let code = AppRunner(output: recorder.output, errorOutput: recorder.error)
            .run(arguments: ["inspect-schema", "--database", databaseURL.path])

        XCTAssertEqual(code, 0)
        XCTAssertTrue(recorder.stdout.contains("Apple Notes schema inspection"))
        XCTAssertTrue(recorder.stdout.contains("ZICCLOUDSYNCINGOBJECT"))
        XCTAssertTrue(recorder.stdout.contains("ZICNOTEDATA"))
        XCTAssertFalse(recorder.stdout.contains("hello note body"))
    }

    func testAccountsCommandPrintsFixtureAccount() throws {
        let directory = try TemporaryDirectory()
        let databaseURL = directory.url.appendingPathComponent("NoteStore.sqlite")
        try SQLiteFixture.createAppleNotesLikeDatabase(at: databaseURL)

        let recorder = OutputRecorder()
        let code = AppRunner(output: recorder.output, errorOutput: recorder.error)
            .run(arguments: ["accounts", "--database", databaseURL.path])

        XCTAssertEqual(code, 0)
        XCTAssertTrue(recorder.stdout.contains("Accounts:"))
        XCTAssertTrue(recorder.stdout.contains("iCloud"))
    }

    func testFoldersCommandPrintsFixtureFolders() throws {
        let directory = try TemporaryDirectory()
        let databaseURL = directory.url.appendingPathComponent("NoteStore.sqlite")
        try SQLiteFixture.createAppleNotesLikeDatabase(at: databaseURL)

        let recorder = OutputRecorder()
        let code = AppRunner(output: recorder.output, errorOutput: recorder.error)
            .run(arguments: ["folders", "--account", "iCloud", "--database", databaseURL.path])

        XCTAssertEqual(code, 0)
        XCTAssertTrue(recorder.stdout.contains("Capture"))
        XCTAssertTrue(recorder.stdout.contains("Capture/Sketches"))
    }

    func testNotesCommandPrintsFixtureNotes() throws {
        let directory = try TemporaryDirectory()
        let databaseURL = directory.url.appendingPathComponent("NoteStore.sqlite")
        try SQLiteFixture.createAppleNotesLikeDatabase(at: databaseURL)

        let recorder = OutputRecorder()
        let code = AppRunner(output: recorder.output, errorOutput: recorder.error)
            .run(arguments: [
                "notes",
                "--account",
                "iCloud",
                "--folder",
                "Capture",
                "--recursive",
                "--database",
                databaseURL.path,
            ])

        XCTAssertEqual(code, 0)
        XCTAssertTrue(recorder.stdout.contains("Fixture note"))
        XCTAssertTrue(recorder.stdout.contains("Nested fixture note"))
        XCTAssertFalse(recorder.stdout.contains("hello note body"))
    }

    func testResolveScopeCommandPrintsAllowedFolders() throws {
        let directory = try TemporaryDirectory()
        let databaseURL = directory.url.appendingPathComponent("NoteStore.sqlite")
        try SQLiteFixture.createAppleNotesLikeDatabase(at: databaseURL)

        let recorder = OutputRecorder()
        let code = AppRunner(output: recorder.output, errorOutput: recorder.error)
            .run(arguments: [
                "resolve-scope",
                "--account",
                "iCloud",
                "--folder",
                "Capture",
                "--recursive",
                "--database",
                databaseURL.path,
            ])

        XCTAssertEqual(code, 0)
        XCTAssertTrue(recorder.stdout.contains("Resolved scope:"))
        XCTAssertTrue(recorder.stdout.contains("Allowed folders: 2"))
        XCTAssertTrue(recorder.stdout.contains("Capture/Sketches"))
    }
}
