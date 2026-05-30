import Foundation
import XCTest
@testable import Notes2MyICORCore

final class ChangeClassifierTests: XCTestCase {
    func testUnknownInScopeNoteBecomesNew() {
        let summary = ChangeClassifier().classify(
            inScopeNotes: [note(uuid: "n1")],
            allCurrentNotes: [note(uuid: "n1")],
            previousStates: [],
            allowedFolderIDs: [1],
            missingGraceCount: 3
        )

        XCTAssertEqual(summary.count(.new), 1)
    }

    func testKnownNoteWithNewerModificationDateBecomesModified() {
        let summary = ChangeClassifier().classify(
            inScopeNotes: [note(uuid: "n1", modified: 2)],
            allCurrentNotes: [note(uuid: "n1", modified: 2)],
            previousStates: [state(uuid: "n1", modified: 1)],
            allowedFolderIDs: [1],
            missingGraceCount: 3
        )

        XCTAssertEqual(summary.count(.modified), 1)
    }

    func testKnownNoteWithSameMetadataBecomesUnchanged() {
        let summary = ChangeClassifier().classify(
            inScopeNotes: [note(uuid: "n1", title: "Same", modified: 1, folderID: 1)],
            allCurrentNotes: [note(uuid: "n1", title: "Same", modified: 1, folderID: 1)],
            previousStates: [state(uuid: "n1", title: "Same", modified: 1, folderPath: "1")],
            allowedFolderIDs: [1],
            missingGraceCount: 3
        )

        XCTAssertEqual(summary.count(.unchanged), 1)
    }

    func testRenamedNoteBecomesMetadataChanged() {
        let summary = ChangeClassifier().classify(
            inScopeNotes: [note(uuid: "n1", title: "New title", modified: 1, folderID: 1)],
            allCurrentNotes: [note(uuid: "n1", title: "New title", modified: 1, folderID: 1)],
            previousStates: [state(uuid: "n1", title: "Old title", modified: 1, folderPath: "1")],
            allowedFolderIDs: [1],
            missingGraceCount: 3
        )

        XCTAssertEqual(summary.count(.metadataChanged), 1)
    }

    func testMovedOutsideScopeBecomesOutOfScope() {
        let summary = ChangeClassifier().classify(
            inScopeNotes: [],
            allCurrentNotes: [note(uuid: "n1", folderID: 99)],
            previousStates: [state(uuid: "n1")],
            allowedFolderIDs: [1],
            missingGraceCount: 3
        )

        XCTAssertEqual(summary.count(.outOfScope), 1)
    }

    func testRecentlyDeletedFolderBecomesRecentlyDeleted() {
        let summary = ChangeClassifier().classify(
            inScopeNotes: [],
            allCurrentNotes: [note(uuid: "n1", folderID: 99)],
            previousStates: [state(uuid: "n1")],
            allowedFolderIDs: [1],
            folders: [
                AppleNotesFolder(objectID: 99, uuid: "recently-deleted", name: "Recently Deleted", accountObjectID: 1, parentObjectID: nil),
            ],
            missingGraceCount: 3
        )

        XCTAssertEqual(summary.count(.recentlyDeleted), 1)
        XCTAssertEqual(summary.count(.outOfScope), 0)
    }

    func testMissingBelowGraceBecomesPossiblyDeleted() {
        let summary = ChangeClassifier().classify(
            inScopeNotes: [],
            allCurrentNotes: [],
            previousStates: [state(uuid: "n1", missingCount: 1)],
            allowedFolderIDs: [1],
            missingGraceCount: 3
        )

        XCTAssertEqual(summary.count(.missingPossiblyDeleted), 1)
    }

    func testMissingAtGraceBecomesDeletedAfterGrace() {
        let summary = ChangeClassifier().classify(
            inScopeNotes: [],
            allCurrentNotes: [],
            previousStates: [state(uuid: "n1", missingCount: 2)],
            allowedFolderIDs: [1],
            missingGraceCount: 3
        )

        XCTAssertEqual(summary.count(.deletedAfterGrace), 1)
    }

    func testFailedExportCanBeRetried() {
        let summary = ChangeClassifier().classify(
            inScopeNotes: [note(uuid: "n1")],
            allCurrentNotes: [note(uuid: "n1")],
            previousStates: [state(uuid: "n1", exportStatus: "failed")],
            allowedFolderIDs: [1],
            missingGraceCount: 3
        )

        XCTAssertEqual(summary.count(.exportFailed), 1)
    }

    private func note(uuid: String, title: String = "Title", modified: Double = 1, folderID: Int = 1) -> AppleNotesNoteMetadata {
        AppleNotesNoteMetadata(
            objectID: 1,
            uuid: uuid,
            title: title,
            snippet: nil,
            createdCoreData: nil,
            modifiedCoreData: modified,
            createdAt: nil,
            modifiedAt: nil,
            accountObjectID: 1,
            folderObjectID: folderID,
            noteDataObjectID: 1
        )
    }

    private func state(
        uuid: String,
        title: String = "Title",
        modified: Double = 1,
        folderPath: String = "1",
        missingCount: Int = 0,
        exportStatus: String = "pending"
    ) -> NoteState {
        NoteState(
            noteUUID: uuid,
            title: title,
            exportStatus: exportStatus,
            modifiedCoreData: modified,
            folderPath: folderPath,
            missingScanCount: missingCount,
            lastSeenAt: "now"
        )
    }
}
