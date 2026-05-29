import Foundation
import XCTest
@testable import Notes2MyICORCore

final class PathTests: XCTestCase {
    func testExpandsTildeToHomeDirectory() {
        let paths = AppPaths(environment: ["HOME": "/tmp/example-home"])

        XCTAssertEqual(paths.expandPath("~").path, "/tmp/example-home")
        XCTAssertEqual(paths.expandPath("~/Library/Application Support").path, "/tmp/example-home/Library/Application Support")
    }

    func testComputesApplicationSupportDirectory() {
        let paths = AppPaths(environment: ["HOME": "/tmp/example-home"])

        XCTAssertEqual(paths.applicationSupportDirectory.path, "/tmp/example-home/Library/Application Support/Notes2MyICOR")
    }

    func testCreatesApplicationSupportDirectory() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appendingPathComponent("home")
        let paths = AppPaths(environment: ["HOME": home.path])

        let created = try paths.createApplicationSupportDirectory()

        XCTAssertTrue(FileManager.default.fileExists(atPath: created.path))
    }
}
