import Foundation
import XCTest
@testable import Notes2MyICORCore

final class AppleCloudNotesParserTests: XCTestCase {
    func testParserBuildsCommandAndDecodesJSON() throws {
        let directory = try TemporaryDirectory()
        let parserScript = directory.url.appendingPathComponent("notes_cloud_ripper.rb")
        let notesContainer = directory.url.appendingPathComponent("group.com.apple.notes", isDirectory: true)
        let outputDirectory = directory.url.appendingPathComponent("parser-output", isDirectory: true)
        try Data("# parser".utf8).write(to: parserScript)
        try FileManager.default.createDirectory(at: notesContainer, withIntermediateDirectories: true)

        let runner = FakeParserRunner(outputDirectory: outputDirectory)
        let parser = AppleCloudNotesParser(
            config: AppleCloudNotesParserConfig(
                rubyExecutablePath: "/ruby",
                parserScriptPath: parserScript.path,
                outputDirectory: outputDirectory
            ),
            runner: runner
        )

        let result = try parser.parse(notesContainer: notesContainer, noteUUIDs: ["note-uuid"])

        XCTAssertEqual(runner.executablePath, "/ruby")
        XCTAssertEqual(runner.arguments.first, parserScript.path)
        XCTAssertTrue(runner.arguments.contains("--mac"))
        XCTAssertTrue(runner.arguments.contains("--one-output-folder"))
        XCTAssertTrue(runner.arguments.contains("--individual-files"))
        XCTAssertTrue(runner.arguments.contains("--uuid"))
        XCTAssertTrue(runner.arguments.contains("--retain-display-order"))
        XCTAssertEqual(result.notes.count, 1)
        XCTAssertEqual(result.notes[0].uuid, "note-uuid")
        XCTAssertEqual(result.notes[0].title, "Parser fixture")
        XCTAssertEqual(result.notes[0].html, "<p>Body</p>")
    }

    func testParserSurfacesSubprocessFailure() throws {
        let directory = try TemporaryDirectory()
        let parserScript = directory.url.appendingPathComponent("notes_cloud_ripper.rb")
        try Data("# parser".utf8).write(to: parserScript)
        let runner = FakeParserRunner(outputDirectory: directory.url, result: ExternalCommandResult(
            exitCode: 1,
            standardOutput: "",
            standardError: "boom"
        ))

        let parser = AppleCloudNotesParser(
            config: AppleCloudNotesParserConfig(
                rubyExecutablePath: "/ruby",
                parserScriptPath: parserScript.path,
                outputDirectory: directory.url
            ),
            runner: runner
        )

        XCTAssertThrowsError(try parser.parse(notesContainer: directory.url)) { error in
            XCTAssertTrue(error.localizedDescription.contains("exit code 1"))
        }
    }

    func testJSONDecoderFiltersByUUIDAndFindsHTMLPath() throws {
        let directory = try TemporaryDirectory()
        let output = directory.url.appendingPathComponent("notes_rip", isDirectory: true)
        let json = output.appendingPathComponent("json/all_notes_1.json")
        let html = output.appendingPathComponent("html/note-uuid.html")
        try FileManager.default.createDirectory(at: json.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: html.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("<html></html>".utf8).write(to: html)
        try Data(
            """
            {
              "notes": {
                "1": {"uuid": "note-uuid", "title": "Wanted", "html": "<p>Wanted</p>"},
                "2": {"uuid": "other-uuid", "title": "Other", "html": "<p>Other</p>"}
              }
            }
            """.utf8
        ).write(to: json)

        let notes = try AppleCloudNotesJSONDecoder().decodeNotes(
            jsonPath: json,
            outputDirectory: output,
            noteUUIDs: ["note-uuid"]
        )

        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(
            notes[0].individualHTMLPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path },
            html.standardizedFileURL.path
        )
    }

    func testJSONDecoderReportsMissingRequestedNote() throws {
        let directory = try TemporaryDirectory()
        let output = directory.url.appendingPathComponent("notes_rip", isDirectory: true)
        let json = output.appendingPathComponent("json/all_notes_1.json")
        try FileManager.default.createDirectory(at: json.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"notes":{}}"#.utf8).write(to: json)

        XCTAssertThrowsError(try AppleCloudNotesJSONDecoder().decodeNotes(
            jsonPath: json,
            outputDirectory: output,
            noteUUIDs: ["missing"]
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("missing"))
        }
    }
}

private final class FakeParserRunner: ExternalCommandRunning {
    private let outputDirectory: URL
    private let result: ExternalCommandResult

    private(set) var executablePath = ""
    private(set) var arguments: [String] = []

    init(
        outputDirectory: URL,
        result: ExternalCommandResult = ExternalCommandResult(exitCode: 0, standardOutput: "ok", standardError: "")
    ) {
        self.outputDirectory = outputDirectory
        self.result = result
    }

    func run(executablePath: String, arguments: [String], workingDirectory: URL?) throws -> ExternalCommandResult {
        self.executablePath = executablePath
        self.arguments = arguments

        if result.exitCode == 0 {
            let json = outputDirectory.appendingPathComponent("notes_rip/json/all_notes_1.json")
            try FileManager.default.createDirectory(at: json.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(#"{"notes":{"1":{"uuid":"note-uuid","title":"Parser fixture","html":"<p>Body</p>"}}}"#.utf8).write(to: json)
        }

        return result
    }
}
