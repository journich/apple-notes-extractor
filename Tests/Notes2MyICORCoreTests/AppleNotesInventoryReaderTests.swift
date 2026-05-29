import Foundation
import XCTest
@testable import Notes2MyICORCore

final class AppleNotesInventoryReaderTests: XCTestCase {
    func testCoreDataTimestampConversion() {
        let date = CoreDataTimestamp.date(fromCoreDataTimestamp: 0)

        XCTAssertEqual(date, Date(timeIntervalSince1970: 978_307_200))
    }

    func testInventoryReaderMapsAccountsFoldersAndNotes() throws {
        let directory = try TemporaryDirectory()
        let databaseURL = directory.url.appendingPathComponent("NoteStore.sqlite")
        try SQLiteFixture.createAppleNotesLikeDatabase(at: databaseURL)

        let inventory = try AppleNotesInventoryReader().readInventory(databaseURL: databaseURL)

        XCTAssertEqual(inventory.accounts, [
            AppleNotesAccount(objectID: 100, uuid: "fixture-account-uuid", name: "iCloud"),
        ])

        XCTAssertEqual(inventory.folders, [
            AppleNotesFolder(
                objectID: 200,
                uuid: "fixture-folder-root-uuid",
                name: "Capture",
                accountObjectID: 100,
                parentObjectID: nil
            ),
            AppleNotesFolder(
                objectID: 201,
                uuid: "fixture-folder-child-uuid",
                name: "Sketches",
                accountObjectID: 100,
                parentObjectID: 200
            ),
        ])

        XCTAssertEqual(inventory.notes.count, 2)
        XCTAssertEqual(inventory.notes[0].uuid, "fixture-child-note-uuid")
        XCTAssertEqual(inventory.notes[0].title, "Nested fixture note")
        XCTAssertNil(inventory.notes[0].snippet)
        XCTAssertEqual(inventory.notes[0].folderObjectID, 201)
        XCTAssertEqual(inventory.notes[0].modifiedAt, Date(timeIntervalSince1970: 978_307_320))
        XCTAssertEqual(inventory.notes[1].uuid, "fixture-note-uuid")
        XCTAssertEqual(inventory.notes[1].snippet, "Fixture snippet")
    }

    func testFolderPathBuilderBuildsNestedPaths() throws {
        let folders = [
            AppleNotesFolder(objectID: 1, uuid: "root", name: "Capture", accountObjectID: 10, parentObjectID: nil),
            AppleNotesFolder(objectID: 2, uuid: "child", name: "Sketches", accountObjectID: 10, parentObjectID: 1),
        ]

        let paths = FolderPathBuilder(folders: folders).pathsByFolderID()

        XCTAssertEqual(paths[1], "Capture")
        XCTAssertEqual(paths[2], "Capture/Sketches")
    }

    func testFormatNotesFiltersByFolderRecursively() throws {
        let directory = try TemporaryDirectory()
        let databaseURL = directory.url.appendingPathComponent("NoteStore.sqlite")
        try SQLiteFixture.createAppleNotesLikeDatabase(at: databaseURL)
        let inventory = try AppleNotesInventoryReader().readInventory(databaseURL: databaseURL)

        let formatted = try AppleNotesInventoryFormatter().formatNotes(
            inventory.notes,
            folders: inventory.folders,
            accounts: inventory.accounts,
            accountName: "iCloud",
            folderPath: "Capture",
            recursive: true
        )

        XCTAssertTrue(formatted.contains("Fixture note"))
        XCTAssertTrue(formatted.contains("Nested fixture note"))
        XCTAssertTrue(formatted.contains("Capture/Sketches"))
    }

    func testFormatNotesFiltersByFolderNonRecursively() throws {
        let directory = try TemporaryDirectory()
        let databaseURL = directory.url.appendingPathComponent("NoteStore.sqlite")
        try SQLiteFixture.createAppleNotesLikeDatabase(at: databaseURL)
        let inventory = try AppleNotesInventoryReader().readInventory(databaseURL: databaseURL)

        let formatted = try AppleNotesInventoryFormatter().formatNotes(
            inventory.notes,
            folders: inventory.folders,
            accounts: inventory.accounts,
            accountName: "iCloud",
            folderPath: "Capture",
            recursive: false
        )

        XCTAssertTrue(formatted.contains("Fixture note"))
        XCTAssertFalse(formatted.contains("Nested fixture note"))
    }

    func testUnknownAccountReportsClearError() throws {
        let directory = try TemporaryDirectory()
        let databaseURL = directory.url.appendingPathComponent("NoteStore.sqlite")
        try SQLiteFixture.createAppleNotesLikeDatabase(at: databaseURL)
        let inventory = try AppleNotesInventoryReader().readInventory(databaseURL: databaseURL)

        XCTAssertThrowsError(try AppleNotesInventoryFormatter().formatFolders(
            inventory.folders,
            accounts: inventory.accounts,
            accountName: "Missing"
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("account not found"))
        }
    }
}
