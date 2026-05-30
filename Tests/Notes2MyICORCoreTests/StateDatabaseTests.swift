import Foundation
import XCTest
@testable import Notes2MyICORCore

final class StateDatabaseTests: XCTestCase {
    func testStateDatabaseIsCreatedAndMigrated() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("state.sqlite")

        let database = try StateDatabase.open(at: url)
        try database.migrate()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try database.schemaVersion(), StateDatabase.currentSchemaVersion)
        XCTAssertEqual(try database.status(), StateDatabaseStatus(
            schemaVersion: StateDatabase.currentSchemaVersion,
            notesCount: 0,
            scanRunsCount: 0,
            syncRootsCount: 0
        ))
    }

    func testMigrationsAreIdempotent() throws {
        let directory = try TemporaryDirectory()
        let database = try migratedDatabase(in: directory)

        try database.migrate()
        try database.migrate()

        XCTAssertEqual(try database.schemaVersion(), StateDatabase.currentSchemaVersion)
    }

    func testNoteStateInsertUpdateAndReset() throws {
        let directory = try TemporaryDirectory()
        let database = try migratedDatabase(in: directory)

        try database.upsertNoteState(NoteState(
            noteUUID: "note-1",
            title: "First title",
            exportStatus: "pending",
            pdfPath: nil,
            contentHash: nil,
            lastSeenAt: "2026-05-30T00:00:00Z"
        ))

        XCTAssertEqual(try database.noteState(noteUUID: "note-1")?.title, "First title")

        try database.upsertNoteState(NoteState(
            noteUUID: "note-1",
            title: "Updated title",
            exportStatus: "exported",
            pdfPath: "/tmp/example.pdf",
            contentHash: "sha256:example",
            lastSeenAt: "2026-05-30T00:01:00Z"
        ))

        let updated = try XCTUnwrap(database.noteState(noteUUID: "note-1"))
        XCTAssertEqual(updated.title, "Updated title")
        XCTAssertEqual(updated.exportStatus, "exported")
        XCTAssertEqual(updated.pdfPath, "/tmp/example.pdf")

        try database.resetNoteState(noteUUID: "note-1")

        XCTAssertNil(try database.noteState(noteUUID: "note-1"))
    }

    func testNoteStatePersistsDeletionPolicyTimestamps() throws {
        let directory = try TemporaryDirectory()
        let database = try migratedDatabase(in: directory)

        try database.upsertNoteState(NoteState(
            noteUUID: "note-1",
            exportStatus: "deleted",
            pdfPath: "/tmp/example.pdf",
            missingScanCount: 3,
            isDeleted: true,
            isInScope: false,
            lastSeenAt: "2026-05-30T00:00:00Z",
            deletedDetectedAt: "2026-05-30T00:00:00Z",
            firstMissingAt: "2026-05-29T00:00:00Z"
        ))

        let state = try XCTUnwrap(database.noteState(noteUUID: "note-1"))
        XCTAssertEqual(state.pdfPath, "/tmp/example.pdf")
        XCTAssertTrue(state.isDeleted)
        XCTAssertFalse(state.isInScope)
        XCTAssertEqual(state.deletedDetectedAt, "2026-05-30T00:00:00Z")
        XCTAssertEqual(state.firstMissingAt, "2026-05-29T00:00:00Z")
    }

    func testScanRunInsertUpdateWorks() throws {
        let directory = try TemporaryDirectory()
        let database = try migratedDatabase(in: directory)

        try database.upsertScanRun(ScanRunState(scanID: "scan-1", startedAt: "start", status: "running", notesSeen: 1))
        try database.upsertScanRun(ScanRunState(
            scanID: "scan-1",
            startedAt: "start",
            completedAt: "end",
            status: "success",
            notesSeen: 2,
            notesExported: 1
        ))

        let status = try database.status()
        XCTAssertEqual(status.scanRunsCount, 1)
    }

    func testSyncRootInsertUpdateWorks() throws {
        let directory = try TemporaryDirectory()
        let database = try migratedDatabase(in: directory)

        try database.upsertSyncRoot(SyncRootState(
            rootID: "root-1",
            accountName: "iCloud",
            folderPath: "Capture",
            recursive: true,
            createdAt: "now"
        ))
        try database.upsertSyncRoot(SyncRootState(
            rootID: "root-1",
            accountName: "iCloud",
            folderPath: "Capture/Sketches",
            recursive: false,
            createdAt: "now"
        ))

        let status = try database.status()
        XCTAssertEqual(status.syncRootsCount, 1)
    }

    func testStatusFormatterIncludesCounts() {
        let formatted = StateDatabaseFormatter().formatStatus(
            StateDatabaseStatus(schemaVersion: 1, notesCount: 2, scanRunsCount: 3, syncRootsCount: 4),
            path: "/tmp/state.sqlite"
        )

        XCTAssertTrue(formatted.contains("Schema version: 1"))
        XCTAssertTrue(formatted.contains("Notes tracked: 2"))
        XCTAssertTrue(formatted.contains("Scan runs: 3"))
        XCTAssertTrue(formatted.contains("Sync roots: 4"))
    }

    private func migratedDatabase(in directory: TemporaryDirectory) throws -> StateDatabase {
        let database = try StateDatabase.open(at: directory.url.appendingPathComponent("state.sqlite"))
        try database.migrate()
        return database
    }
}
