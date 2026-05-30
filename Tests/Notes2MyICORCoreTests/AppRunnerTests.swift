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

    func testStatusCommandCreatesAndPrintsStateDatabaseStatus() throws {
        let directory = try TemporaryDirectory()
        let stateURL = directory.url.appendingPathComponent("state.sqlite")
        let recorder = OutputRecorder()

        let code = AppRunner(output: recorder.output, errorOutput: recorder.error)
            .run(arguments: ["status", "--state-db", stateURL.path])

        XCTAssertEqual(code, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))
        XCTAssertTrue(recorder.stdout.contains("State database:"))
        XCTAssertTrue(recorder.stdout.contains("Schema version: 1"))
    }

    func testResetStateCommandDeletesRequestedNote() throws {
        let directory = try TemporaryDirectory()
        let stateURL = directory.url.appendingPathComponent("state.sqlite")
        let database = try StateDatabase.open(at: stateURL)
        try database.migrate()
        try database.upsertNoteState(NoteState(noteUUID: "note-1", title: "Title", lastSeenAt: "now"))

        let recorder = OutputRecorder()
        let code = AppRunner(output: recorder.output, errorOutput: recorder.error)
            .run(arguments: ["reset-state", "--note-uuid", "note-1", "--state-db", stateURL.path])

        XCTAssertEqual(code, 0)
        XCTAssertNil(try database.noteState(noteUUID: "note-1"))
        XCTAssertTrue(recorder.stdout.contains("Reset state for note: note-1"))
    }

    func testScanCommandPrintsSummaryAndUpdatesState() throws {
        let directory = try TemporaryDirectory()
        let databaseURL = directory.url.appendingPathComponent("NoteStore.sqlite")
        let stateURL = directory.url.appendingPathComponent("state.sqlite")
        try SQLiteFixture.createAppleNotesLikeDatabase(at: databaseURL)

        let recorder = OutputRecorder()
        let code = AppRunner(output: recorder.output, errorOutput: recorder.error)
            .run(arguments: [
                "scan",
                "--account",
                "iCloud",
                "--folder",
                "Capture",
                "--recursive",
                "--database",
                databaseURL.path,
                "--state-db",
                stateURL.path,
            ])

        XCTAssertEqual(code, 0)
        XCTAssertTrue(recorder.stdout.contains("Scan summary:"))
        XCTAssertTrue(recorder.stdout.contains("NEW: 2"))

        let stateDatabase = try StateDatabase.open(at: stateURL)
        try stateDatabase.migrate()
        XCTAssertEqual(try stateDatabase.status().notesCount, 2)
    }

    func testSnapshotCommandCreatesSnapshotInWorkDirectory() throws {
        let directory = try TemporaryDirectory()
        let source = directory.url.appendingPathComponent("group.com.apple.notes", isDirectory: true)
        let work = directory.url.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("sqlite".utf8).write(to: source.appendingPathComponent("NoteStore.sqlite"))

        let recorder = OutputRecorder()
        let code = AppRunner(output: recorder.output, errorOutput: recorder.error)
            .run(arguments: ["snapshot", "--notes-container", source.path, "--work-dir", work.path])

        XCTAssertEqual(code, 0)
        XCTAssertTrue(recorder.stdout.contains("Snapshot created:"))
        XCTAssertTrue(recorder.stdout.contains("NoteStore.sqlite"))
    }

    func testParseCommandReportsMissingParserScript() throws {
        let recorder = OutputRecorder()
        let code = AppRunner(output: recorder.output, errorOutput: recorder.error)
            .run(arguments: ["parse", "--parser-script", "/missing/parser.rb"])

        XCTAssertEqual(code, 1)
        XCTAssertTrue(recorder.stderr.contains("Parser script not found"))
    }

    func testExportCommandRendersHTMLFixture() throws {
        let directory = try TemporaryDirectory()
        let htmlURL = directory.url.appendingPathComponent("fixture.html")
        let outputURL = directory.url.appendingPathComponent("output", isDirectory: true)
        try Data("<p>Fixture body</p>".utf8).write(to: htmlURL)

        let recorder = OutputRecorder()
        let code = AppRunner(
            pdfRenderer: AppRunnerFakePDFRenderer(),
            output: recorder.output,
            errorOutput: recorder.error
        )
        .run(arguments: [
            "export",
            "--note-uuid", "fixture-uuid",
            "--title", "Fixture",
            "--html", htmlURL.path,
            "--output-dir", outputURL.path,
            "--debug-html",
        ])

        XCTAssertEqual(code, 0)
        XCTAssertTrue(recorder.stdout.contains("Export complete:"))
        XCTAssertTrue(recorder.stdout.contains("PDF:"))
        XCTAssertTrue(recorder.stdout.contains("Sidecar JSON:"))
        XCTAssertTrue(recorder.stdout.contains("Debug HTML:"))
    }

    func testSyncCommandRequiresOnce() throws {
        let recorder = OutputRecorder()
        let code = AppRunner(output: recorder.output, errorOutput: recorder.error)
            .run(arguments: ["sync"])

        XCTAssertEqual(code, 2)
        XCTAssertTrue(recorder.stderr.contains("Missing required option: --once or --watch"))
    }

    func testSyncWatchCanBeLimitedToZeroRuns() throws {
        let recorder = OutputRecorder()
        let code = AppRunner(output: recorder.output, errorOutput: recorder.error)
            .run(arguments: ["sync", "--watch", "--interval-seconds", "1", "--max-runs", "0"])

        XCTAssertEqual(code, 0)
        XCTAssertTrue(recorder.stdout.contains("Watch completed: runs=0"))
    }

    func testInstallLaunchAgentWritesPlist() throws {
        let directory = try TemporaryDirectory()
        let binaryURL = directory.url.appendingPathComponent("notes2myicor")
        let launchAgentsDirectory = directory.url.appendingPathComponent("LaunchAgents", isDirectory: true)
        let logDirectory = directory.url.appendingPathComponent("Logs", isDirectory: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binaryURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)

        let recorder = OutputRecorder()
        let code = AppRunner(output: recorder.output, errorOutput: recorder.error)
            .run(arguments: [
                "install-launch-agent",
                "--label", "com.example.notes2myicor",
                "--binary", binaryURL.path,
                "--launch-agents-dir", launchAgentsDirectory.path,
                "--log-dir", logDirectory.path,
                "--interval-seconds", "60",
                "--account", "iCloud",
                "--folder", "Capture",
                "--recursive",
            ])

        let plistURL = launchAgentsDirectory.appendingPathComponent("com.example.notes2myicor.plist")
        XCTAssertEqual(code, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertTrue(recorder.stdout.contains("LaunchAgent installed:"))
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
        XCTAssertEqual(plist["StartInterval"] as? Int, 60)
        XCTAssertEqual(plist["StandardOutPath"] as? String, logDirectory.appendingPathComponent("notes2myicor.out.log").path)
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [
            binaryURL.path,
            "sync",
            "--once",
            "--account",
            "iCloud",
            "--folder",
            "Capture",
            "--recursive",
        ])
    }

    func testLaunchAgentStatusReportsInstalledState() throws {
        let directory = try TemporaryDirectory()
        let launchAgentsDirectory = directory.url.appendingPathComponent("LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        try Data("plist".utf8).write(
            to: launchAgentsDirectory.appendingPathComponent("com.example.notes2myicor.plist")
        )

        let recorder = OutputRecorder()
        let code = AppRunner(output: recorder.output, errorOutput: recorder.error)
            .run(arguments: [
                "launch-agent-status",
                "--label", "com.example.notes2myicor",
                "--launch-agents-dir", launchAgentsDirectory.path,
            ])

        XCTAssertEqual(code, 0)
        XCTAssertTrue(recorder.stdout.contains("INSTALLED: true"))
    }

    func testUninstallLaunchAgentRemovesPlist() throws {
        let directory = try TemporaryDirectory()
        let launchAgentsDirectory = directory.url.appendingPathComponent("LaunchAgents", isDirectory: true)
        let plistURL = launchAgentsDirectory.appendingPathComponent("com.example.notes2myicor.plist")
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        try Data("plist".utf8).write(to: plistURL)

        let recorder = OutputRecorder()
        let code = AppRunner(output: recorder.output, errorOutput: recorder.error)
            .run(arguments: [
                "uninstall-launch-agent",
                "--label", "com.example.notes2myicor",
                "--launch-agents-dir", launchAgentsDirectory.path,
            ])

        XCTAssertEqual(code, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
    }
}

private final class AppRunnerFakePDFRenderer: PDFRendering {
    func renderPDF(html: String, baseURL: URL?) throws -> Data {
        Data("%PDF fake".utf8)
    }
}
