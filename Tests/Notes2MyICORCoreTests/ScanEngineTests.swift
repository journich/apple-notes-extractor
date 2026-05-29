import Foundation
import XCTest
@testable import Notes2MyICORCore

final class ScanEngineTests: XCTestCase {
    func testScanExportsNewThenUnchangedClassifications() throws {
        let directory = try TemporaryDirectory()
        let notesURL = directory.url.appendingPathComponent("NoteStore.sqlite")
        let stateURL = directory.url.appendingPathComponent("state.sqlite")
        try SQLiteFixture.createAppleNotesLikeDatabase(at: notesURL)

        let stateDatabase = try StateDatabase.open(at: stateURL)
        let engine = ScanEngine(stateDatabase: stateDatabase, now: { Date(timeIntervalSince1970: 0) })

        let first = try engine.scan(
            databaseURL: notesURL,
            scopeRequest: AppleNotesScopeRequest(accountName: "iCloud", folderPath: "Capture", recursive: true),
            missingGraceCount: 3
        )
        let second = try engine.scan(
            databaseURL: notesURL,
            scopeRequest: AppleNotesScopeRequest(accountName: "iCloud", folderPath: "Capture", recursive: true),
            missingGraceCount: 3
        )

        XCTAssertEqual(first.count(.new), 2)
        XCTAssertEqual(second.count(.unchanged), 2)
        XCTAssertEqual(try stateDatabase.status().scanRunsCount, 2)
    }
}
