import Foundation
import XCTest
@testable import Notes2MyICORCore

final class ReleaseReadinessTests: XCTestCase {
    func testExampleConfigParsesSuccessfully() throws {
        let url = repositoryRoot().appendingPathComponent("examples/config.example.json")

        let config = try ConfigStore().load(from: url)

        XCTAssertEqual(config.scope.accountName, "iCloud")
        XCTAssertEqual(config.scope.folderPath, "/")
        XCTAssertEqual(config.export.embeddedPDFMode, "append")
        XCTAssertEqual(config.parser.mode, "apple-cloud-notes-parser")
    }

    func testThirdPartyNoticeExistsForParserIntegration() throws {
        let url = repositoryRoot().appendingPathComponent("THIRD_PARTY_NOTICES.md")
        let text = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(text.contains("Apple Cloud Notes Parser"))
        XCTAssertTrue(text.contains("MIT License"))
        XCTAssertTrue(text.contains("Three Planets Software"))
    }

    func testReleaseMetadataContainsRequiredFields() throws {
        let url = repositoryRoot().appendingPathComponent("release-metadata.json")
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["name"] as? String, "notes2myicor")
        XCTAssertEqual(json["repository"] as? String, "https://github.com/journich/apple-notes-extractor")
        XCTAssertEqual(json["minimum_macos"] as? String, "11.0")
        XCTAssertEqual(json["binary_name"] as? String, "notes2myicor")
        XCTAssertEqual(json["launch_agent_label"] as? String, LaunchAgentDefaults.label)
        XCTAssertEqual(json["release_artifacts"] as? [String], ["notes2myicor"])
    }

    func testReleaseBuildScriptExistsAndIsExecutable() throws {
        let url = repositoryRoot().appendingPathComponent("scripts/build-release.sh")
        let text = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: url.path))
        XCTAssertTrue(text.contains("swift build -c release"))
        XCTAssertTrue(text.contains("notes2myicor"))
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
