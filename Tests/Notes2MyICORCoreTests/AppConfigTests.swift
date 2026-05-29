import Foundation
import XCTest
@testable import Notes2MyICORCore

final class AppConfigTests: XCTestCase {
    func testDefaultConfigHasExpectedValues() {
        let config = AppConfig.defaultConfig

        XCTAssertEqual(config.scope.accountName, "iCloud")
        XCTAssertTrue(config.scope.recursive)
        XCTAssertEqual(config.paths.notesGroupContainer, "~/Library/Group Containers/group.com.apple.notes")
        XCTAssertEqual(config.polling.intervalSeconds, 300)
        XCTAssertTrue(config.export.writeSidecarJSON)
        XCTAssertEqual(config.parser.mode, "apple-cloud-notes-parser")
    }

    func testConfigRoundTripsAsJSON() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("config.json")
        let store = ConfigStore()

        try store.writeDefaultConfig(to: url)
        let loaded = try store.load(from: url)

        XCTAssertEqual(loaded, AppConfig.defaultConfig)
    }

    func testMissingConfigReportsClearError() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("missing.json")
        let store = ConfigStore()

        do {
            _ = try store.load(from: url)
            XCTFail("Expected missing config error")
        } catch let error as ConfigError {
            XCTAssertTrue(error.errorDescription?.contains("Config file not found") == true)
        }
    }

    func testInvalidConfigReportsClearError() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("invalid.json")
        try Data("{ invalid json".utf8).write(to: url)

        do {
            _ = try ConfigStore().load(from: url)
            XCTFail("Expected invalid config error")
        } catch let error as ConfigError {
            XCTAssertTrue(error.errorDescription?.contains("Invalid config file") == true)
        }
    }

    func testWritingDefaultConfigDoesNotOverwriteByDefault() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("config.json")
        let store = ConfigStore()

        try store.writeDefaultConfig(to: url)

        do {
            try store.writeDefaultConfig(to: url)
            XCTFail("Expected existing config error")
        } catch let error as ConfigError {
            XCTAssertTrue(error.errorDescription?.contains("already exists") == true)
        }
    }
}
