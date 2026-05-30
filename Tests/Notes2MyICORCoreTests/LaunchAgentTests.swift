import Foundation
import XCTest
@testable import Notes2MyICORCore

final class LaunchAgentTests: XCTestCase {
    func testPlistContainsExpectedLabelAndProgramArguments() throws {
        let config = makeConfig()
        let plist = try decodePlist(config)

        XCTAssertEqual(plist["Label"] as? String, "com.example.notes2myicor")
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [
            "/usr/local/bin/notes2myicor",
            "sync",
            "--once",
            "--account",
            "iCloud",
            "--folder",
            "Capture",
            "--recursive",
        ])
    }

    func testPlistContainsPollIntervalAndLogPaths() throws {
        let config = makeConfig(intervalSeconds: 120)
        let plist = try decodePlist(config)

        XCTAssertEqual(plist["StartInterval"] as? Int, 120)
        XCTAssertEqual(plist["StandardOutPath"] as? String, "/tmp/notes2myicor.out.log")
        XCTAssertEqual(plist["StandardErrorPath"] as? String, "/tmp/notes2myicor.err.log")
    }

    func testPlistGenerationIsDeterministic() throws {
        let config = makeConfig()
        let generator = LaunchAgentPlistGenerator()

        let first = try generator.plistData(for: config)
        let second = try generator.plistData(for: config)

        XCTAssertEqual(first, second)
    }

    func testInstallRefusesRelativeBinaryPath() throws {
        let directory = try TemporaryDirectory()
        let config = LaunchAgentConfig(
            label: "com.example.notes2myicor",
            executableURL: try XCTUnwrap(URL(string: "notes2myicor")),
            syncArguments: ["sync", "--once"],
            standardOutURL: URL(fileURLWithPath: "/tmp/out.log"),
            standardErrorURL: URL(fileURLWithPath: "/tmp/err.log")
        )

        XCTAssertThrowsError(try LaunchAgentManager().install(
            config,
            launchAgentsDirectory: directory.url
        )) { error in
            XCTAssertEqual(error as? LaunchAgentError, .unsafeBinaryPath("notes2myicor"))
        }
    }

    func testInstallWritesPlistAndStatusDetectsIt() throws {
        let directory = try TemporaryDirectory()
        let binaryURL = directory.url.appendingPathComponent("notes2myicor")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binaryURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)

        let config = LaunchAgentConfig(
            label: "com.example.notes2myicor",
            executableURL: binaryURL,
            syncArguments: ["sync", "--once"],
            standardOutURL: directory.url.appendingPathComponent("out.log"),
            standardErrorURL: directory.url.appendingPathComponent("err.log")
        )
        let manager = LaunchAgentManager()

        let plistURL = try manager.install(config, launchAgentsDirectory: directory.url)
        let status = try manager.status(label: config.label, launchAgentsDirectory: directory.url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertTrue(status.isInstalled)
        XCTAssertEqual(status.plistURL, plistURL)
    }

    func testUninstallRemovesPlist() throws {
        let directory = try TemporaryDirectory()
        let plistURL = directory.url.appendingPathComponent("com.example.notes2myicor.plist")
        try Data("plist".utf8).write(to: plistURL)

        _ = try LaunchAgentManager().uninstall(
            label: "com.example.notes2myicor",
            launchAgentsDirectory: directory.url
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
    }

    private func makeConfig(intervalSeconds: Int = 300) -> LaunchAgentConfig {
        LaunchAgentConfig(
            label: "com.example.notes2myicor",
            executableURL: URL(fileURLWithPath: "/usr/local/bin/notes2myicor"),
            syncArguments: [
                "sync",
                "--once",
                "--account",
                "iCloud",
                "--folder",
                "Capture",
                "--recursive",
            ],
            intervalSeconds: intervalSeconds,
            standardOutURL: URL(fileURLWithPath: "/tmp/notes2myicor.out.log"),
            standardErrorURL: URL(fileURLWithPath: "/tmp/notes2myicor.err.log")
        )
    }

    private func decodePlist(_ config: LaunchAgentConfig) throws -> [String: Any] {
        let data = try LaunchAgentPlistGenerator().plistData(for: config)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }
}
