import Foundation
import XCTest
@testable import Notes2MyICORCore

final class AppleNotesScopeResolverTests: XCTestCase {
    func testResolvesSimpleRootFolder() throws {
        let resolution = try AppleNotesScopeResolver().resolve(
            AppleNotesScopeRequest(accountName: "iCloud", folderPath: "Capture", recursive: false),
            inventory: scopeFixtureInventory()
        )

        XCTAssertEqual(resolution.account.objectID, 100)
        XCTAssertEqual(resolution.rootFolder.objectID, 200)
        XCTAssertEqual(resolution.allowedFolderIDs, [200])
    }

    func testResolvesNestedFolderPath() throws {
        let resolution = try AppleNotesScopeResolver().resolve(
            AppleNotesScopeRequest(accountName: "iCloud", folderPath: "Capture/Sketches", recursive: false),
            inventory: scopeFixtureInventory()
        )

        XCTAssertEqual(resolution.rootFolder.objectID, 201)
        XCTAssertEqual(resolution.rootFolderPath, "Capture/Sketches")
    }

    func testRecursiveScopeIncludesDescendants() throws {
        let resolution = try AppleNotesScopeResolver().resolve(
            AppleNotesScopeRequest(accountName: "iCloud", folderPath: "Capture", recursive: true),
            inventory: scopeFixtureInventory()
        )

        XCTAssertEqual(resolution.allowedFolderIDs, [200, 201, 202])
    }

    func testNonRecursiveScopeIncludesOnlyRoot() throws {
        let resolution = try AppleNotesScopeResolver().resolve(
            AppleNotesScopeRequest(accountName: "iCloud", folderPath: "Capture", recursive: false),
            inventory: scopeFixtureInventory()
        )

        XCTAssertEqual(resolution.allowedFolderIDs, [200])
    }

    func testDuplicateFolderNamesUnderDifferentParentsResolveByFullPath() throws {
        let resolution = try AppleNotesScopeResolver().resolve(
            AppleNotesScopeRequest(accountName: "iCloud", folderPath: "Archive/Sketches", recursive: false),
            inventory: scopeFixtureInventory()
        )

        XCTAssertEqual(resolution.rootFolder.objectID, 204)
    }

    func testDuplicateFolderNamesUnderDifferentAccountsResolveByAccount() throws {
        let resolution = try AppleNotesScopeResolver().resolve(
            AppleNotesScopeRequest(accountName: "On My Mac", folderPath: "Capture", recursive: false),
            inventory: scopeFixtureInventory()
        )

        XCTAssertEqual(resolution.account.objectID, 101)
        XCTAssertEqual(resolution.rootFolder.objectID, 300)
    }

    func testMissingAccountProducesClearError() {
        XCTAssertThrowsError(try AppleNotesScopeResolver().resolve(
            AppleNotesScopeRequest(accountName: "Missing", folderPath: "Capture", recursive: false),
            inventory: scopeFixtureInventory()
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("account not found"))
        }
    }

    func testMissingFolderPathProducesClearError() {
        XCTAssertThrowsError(try AppleNotesScopeResolver().resolve(
            AppleNotesScopeRequest(accountName: "iCloud", folderPath: "Missing", recursive: false),
            inventory: scopeFixtureInventory()
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("folder path not found"))
        }
    }

    func testAmbiguousFolderPathProducesClearError() {
        var inventory = scopeFixtureInventory()
        inventory.folders.append(AppleNotesFolder(
            objectID: 205,
            uuid: "duplicate-root",
            name: "Capture",
            accountObjectID: 100,
            parentObjectID: nil
        ))

        XCTAssertThrowsError(try AppleNotesScopeResolver().resolve(
            AppleNotesScopeRequest(accountName: "iCloud", folderPath: "Capture", recursive: false),
            inventory: inventory
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("ambiguous"))
        }
    }

    func testFormatterPrintsAllowedFolderIDs() throws {
        let resolution = try AppleNotesScopeResolver().resolve(
            AppleNotesScopeRequest(accountName: "iCloud", folderPath: "Capture", recursive: true),
            inventory: scopeFixtureInventory()
        )

        let formatted = ScopeResolutionFormatter().format(resolution)

        XCTAssertTrue(formatted.contains("Resolved scope:"))
        XCTAssertTrue(formatted.contains("Allowed folders: 3"))
        XCTAssertTrue(formatted.contains("Capture/Sketches/Deep"))
    }
}

private func scopeFixtureInventory() -> AppleNotesInventory {
    AppleNotesInventory(
        accounts: [
            AppleNotesAccount(objectID: 100, uuid: "icloud-account", name: "iCloud"),
            AppleNotesAccount(objectID: 101, uuid: "local-account", name: "On My Mac"),
        ],
        folders: [
            AppleNotesFolder(objectID: 200, uuid: "capture", name: "Capture", accountObjectID: 100, parentObjectID: nil),
            AppleNotesFolder(objectID: 201, uuid: "sketches", name: "Sketches", accountObjectID: 100, parentObjectID: 200),
            AppleNotesFolder(objectID: 202, uuid: "deep", name: "Deep", accountObjectID: 100, parentObjectID: 201),
            AppleNotesFolder(objectID: 203, uuid: "archive", name: "Archive", accountObjectID: 100, parentObjectID: nil),
            AppleNotesFolder(objectID: 204, uuid: "archive-sketches", name: "Sketches", accountObjectID: 100, parentObjectID: 203),
            AppleNotesFolder(objectID: 300, uuid: "local-capture", name: "Capture", accountObjectID: 101, parentObjectID: nil),
        ],
        notes: []
    )
}
