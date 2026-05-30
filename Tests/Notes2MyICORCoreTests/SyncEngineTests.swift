import Foundation
import XCTest
@testable import Notes2MyICORCore

final class SyncEngineTests: XCTestCase {
    func testSyncEngineExportsNewNotes() throws {
        let harness = try SyncHarness(notes: [Self.note(uuid: "note-1")])

        let summary = try harness.engine.syncOnce(harness.request())

        XCTAssertEqual(summary.exported, 1)
        XCTAssertEqual(harness.exporter.exportedUUIDs, ["note-1"])
        let state = try XCTUnwrap(harness.database.noteState(noteUUID: "note-1"))
        XCTAssertEqual(state.exportStatus, "exported")
        XCTAssertNotNil(state.pdfPath)
        XCTAssertTrue(state.contentHash?.hasPrefix("sha256:") == true)
        XCTAssertEqual(try harness.database.status().scanRunsCount, 1)
    }

    func testSyncEngineExportsModifiedNotes() throws {
        let note = Self.note(uuid: "note-1", modifiedCoreData: 20)
        let harness = try SyncHarness(notes: [note])
        try harness.database.migrate()
        try harness.database.upsertNoteState(NoteState(
            noteUUID: "note-1",
            title: "Fixture",
            exportStatus: "exported",
            pdfPath: "/tmp/old.pdf",
            contentHash: "sha256:old",
            modifiedCoreData: 10,
            folderPath: "10",
            lastSeenAt: "old"
        ))

        let summary = try harness.engine.syncOnce(harness.request())

        XCTAssertEqual(summary.exported, 1)
        XCTAssertEqual(harness.exporter.exportedUUIDs, ["note-1"])
    }

    func testSyncEngineSkipsUnchangedNotes() throws {
        let note = Self.note(uuid: "note-1", modifiedCoreData: 10)
        let harness = try SyncHarness(notes: [note])
        try harness.database.migrate()
        try harness.database.upsertNoteState(NoteState(
            noteUUID: "note-1",
            title: "Fixture",
            exportStatus: "exported",
            pdfPath: "/tmp/old.pdf",
            contentHash: "sha256:old",
            modifiedCoreData: 10,
            folderPath: "10",
            lastSeenAt: "old"
        ))

        let summary = try harness.engine.syncOnce(harness.request())

        XCTAssertEqual(summary.skippedUnchanged, 1)
        XCTAssertEqual(summary.exported, 0)
        XCTAssertEqual(harness.exporter.exportedUUIDs, [])
    }

    func testSyncEngineDoesNotMarkSuccessIfParsingFails() throws {
        let harness = try SyncHarness(notes: [Self.note(uuid: "note-1")], parserThrows: true)

        let summary = try harness.engine.syncOnce(harness.request())

        XCTAssertEqual(summary.failed, 1)
        let state = try XCTUnwrap(harness.database.noteState(noteUUID: "note-1"))
        XCTAssertEqual(state.exportStatus, "failed")
        XCTAssertNil(state.pdfPath)
    }

    func testSyncEngineDoesNotMarkSuccessIfPDFWritingFails() throws {
        let harness = try SyncHarness(notes: [Self.note(uuid: "note-1")], exporterFailures: ["note-1"])

        let summary = try harness.engine.syncOnce(harness.request())

        XCTAssertEqual(summary.failed, 1)
        let state = try XCTUnwrap(harness.database.noteState(noteUUID: "note-1"))
        XCTAssertEqual(state.exportStatus, "failed")
        XCTAssertNil(state.pdfPath)
    }

    func testPerNoteFailureDoesNotStopLaterNotes() throws {
        let harness = try SyncHarness(
            notes: [Self.note(uuid: "note-1"), Self.note(uuid: "note-2")],
            exporterFailures: ["note-1"]
        )

        let summary = try harness.engine.syncOnce(harness.request())

        XCTAssertEqual(summary.exported, 1)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(harness.exporter.exportedUUIDs, ["note-1", "note-2"])
        XCTAssertEqual(try harness.database.noteState(noteUUID: "note-1")?.exportStatus, "failed")
        XCTAssertEqual(try harness.database.noteState(noteUUID: "note-2")?.exportStatus, "exported")
    }

    func testContentHashPreventsUnnecessaryRewrite() throws {
        let note = Self.note(uuid: "note-1", modifiedCoreData: 20)
        let parsed = Self.parsed(uuid: "note-1", html: "<p>Same</p>")
        let document = NoteDocumentBuilder().document(
            parsedNote: parsed,
            metadata: note,
            accountName: "iCloud",
            folderPath: "Capture"
        )
        let existingHash = "sha256:\(NoteDocumentHasher().contentHash(for: document))"
        let harness = try SyncHarness(notes: [note], parsedNotes: [parsed])
        try harness.database.migrate()
        try harness.database.upsertNoteState(NoteState(
            noteUUID: "note-1",
            title: "Fixture",
            exportStatus: "exported",
            pdfPath: "/tmp/existing.pdf",
            contentHash: existingHash,
            modifiedCoreData: 10,
            folderPath: "10",
            lastSeenAt: "old"
        ))

        let summary = try harness.engine.syncOnce(harness.request())

        XCTAssertEqual(summary.skippedContentUnchanged, 1)
        XCTAssertEqual(summary.exported, 0)
        XCTAssertEqual(harness.exporter.exportedUUIDs, [])
        XCTAssertEqual(try harness.database.noteState(noteUUID: "note-1")?.pdfPath, "/tmp/existing.pdf")
    }

    func testDryRunDoesNotWriteStateOrFiles() throws {
        let harness = try SyncHarness(notes: [Self.note(uuid: "note-1")])

        let summary = try harness.engine.syncOnce(harness.request(dryRun: true))

        XCTAssertTrue(summary.dryRun)
        XCTAssertEqual(summary.changeSummary.count(.new), 1)
        XCTAssertEqual(summary.exported, 0)
        XCTAssertEqual(harness.exporter.exportedUUIDs, [])
        XCTAssertNil(try harness.database.noteState(noteUUID: "note-1"))
    }

    func testMissingBelowThresholdPreservesActivePDF() throws {
        let harness = try SyncHarness(notes: [])
        try harness.database.migrate()
        try harness.database.upsertNoteState(Self.exportedState(missingScanCount: 0))

        let summary = try harness.engine.syncOnce(harness.request())

        XCTAssertEqual(summary.changeSummary.count(.missingPossiblyDeleted), 1)
        let state = try XCTUnwrap(harness.database.noteState(noteUUID: "note-1"))
        XCTAssertEqual(state.pdfPath, "/tmp/existing.pdf")
        XCTAssertEqual(state.missingScanCount, 1)
        XCTAssertFalse(state.isDeleted)
        XCTAssertEqual(state.firstMissingAt, "1970-01-01T00:01:40Z")
        XCTAssertNil(state.deletedDetectedAt)
    }

    func testMissingAtThresholdMarksDeletedAndPreservesPDF() throws {
        let harness = try SyncHarness(notes: [])
        try harness.database.migrate()
        try harness.database.upsertNoteState(Self.exportedState(missingScanCount: 2))

        let summary = try harness.engine.syncOnce(harness.request())

        XCTAssertEqual(summary.changeSummary.count(.deletedAfterGrace), 1)
        let state = try XCTUnwrap(harness.database.noteState(noteUUID: "note-1"))
        XCTAssertEqual(state.pdfPath, "/tmp/existing.pdf")
        XCTAssertEqual(state.exportStatus, "deleted")
        XCTAssertEqual(state.missingScanCount, 3)
        XCTAssertTrue(state.isDeleted)
        XCTAssertEqual(state.deletedDetectedAt, "1970-01-01T00:01:40Z")
    }

    func testOutOfScopeNoteIsNotMarkedDeletedAndPreservesPDF() throws {
        let harness = try SyncHarness(
            notes: [Self.note(uuid: "note-1", folderID: 20)],
            folders: SyncHarness.defaultFolders + [
                AppleNotesFolder(objectID: 20, uuid: "archive", name: "Archive", accountObjectID: 1, parentObjectID: nil),
            ]
        )
        try harness.database.migrate()
        try harness.database.upsertNoteState(Self.exportedState())

        let summary = try harness.engine.syncOnce(harness.request())

        XCTAssertEqual(summary.changeSummary.count(.outOfScope), 1)
        let state = try XCTUnwrap(harness.database.noteState(noteUUID: "note-1"))
        XCTAssertEqual(state.pdfPath, "/tmp/existing.pdf")
        XCTAssertEqual(state.exportStatus, "out_of_scope")
        XCTAssertFalse(state.isDeleted)
        XCTAssertFalse(state.isInScope)
    }

    func testRecentlyDeletedNoteIsSoftDeletedAndPreservesPDF() throws {
        let harness = try SyncHarness(
            notes: [Self.note(uuid: "note-1", folderID: 99)],
            folders: SyncHarness.defaultFolders + [
                AppleNotesFolder(objectID: 99, uuid: "recently-deleted", name: "Recently Deleted", accountObjectID: 1, parentObjectID: nil),
            ]
        )
        try harness.database.migrate()
        try harness.database.upsertNoteState(Self.exportedState())

        let summary = try harness.engine.syncOnce(harness.request())

        XCTAssertEqual(summary.changeSummary.count(.recentlyDeleted), 1)
        let state = try XCTUnwrap(harness.database.noteState(noteUUID: "note-1"))
        XCTAssertEqual(state.pdfPath, "/tmp/existing.pdf")
        XCTAssertEqual(state.exportStatus, "soft_deleted")
        XCTAssertTrue(state.isDeleted)
        XCTAssertFalse(state.isInScope)
        XCTAssertEqual(state.deletedDetectedAt, "1970-01-01T00:01:40Z")
    }

    func testDeletionPolicyIsIdempotent() throws {
        let harness = try SyncHarness(notes: [])
        try harness.database.migrate()
        try harness.database.upsertNoteState(Self.exportedState(
            exportStatus: "deleted",
            missingScanCount: 3,
            isDeleted: true,
            deletedDetectedAt: "first-delete",
            firstMissingAt: "first-missing"
        ))

        _ = try harness.engine.syncOnce(harness.request())
        _ = try harness.engine.syncOnce(harness.request())

        let state = try XCTUnwrap(harness.database.noteState(noteUUID: "note-1"))
        XCTAssertEqual(state.pdfPath, "/tmp/existing.pdf")
        XCTAssertEqual(state.deletedDetectedAt, "first-delete")
        XCTAssertEqual(state.firstMissingAt, "first-missing")
        XCTAssertTrue(state.isDeleted)
    }

    private static func note(uuid: String, modifiedCoreData: Double = 10, folderID: Int = 10) -> AppleNotesNoteMetadata {
        AppleNotesNoteMetadata(
            objectID: uuid == "note-1" ? 101 : 102,
            uuid: uuid,
            title: "Fixture",
            snippet: nil,
            createdCoreData: 1,
            modifiedCoreData: modifiedCoreData,
            createdAt: Date(timeIntervalSince1970: 1),
            modifiedAt: Date(timeIntervalSince1970: modifiedCoreData),
            accountObjectID: 1,
            folderObjectID: folderID,
            noteDataObjectID: nil
        )
    }

    private static func exportedState(
        exportStatus: String = "exported",
        missingScanCount: Int = 0,
        isDeleted: Bool = false,
        deletedDetectedAt: String? = nil,
        firstMissingAt: String? = nil
    ) -> NoteState {
        NoteState(
            noteUUID: "note-1",
            title: "Fixture",
            exportStatus: exportStatus,
            pdfPath: "/tmp/existing.pdf",
            contentHash: "sha256:existing",
            modifiedCoreData: 10,
            folderPath: "10",
            missingScanCount: missingScanCount,
            isDeleted: isDeleted,
            lastSeenAt: "old",
            deletedDetectedAt: deletedDetectedAt,
            firstMissingAt: firstMissingAt
        )
    }

    fileprivate static func parsed(uuid: String, html: String? = nil) -> AppleCloudNotesParsedNote {
        AppleCloudNotesParsedNote(
            uuid: uuid,
            title: "Fixture",
            html: html ?? "<p>\(uuid)</p>",
            jsonID: uuid,
            individualHTMLPath: nil
        )
    }
}

private final class SyncHarness {
    let directory: TemporaryDirectory
    let database: StateDatabase
    let parser: FakeSyncParser
    let exporter: FakeSyncExporter
    let engine: SyncEngine

    init(
        notes: [AppleNotesNoteMetadata],
        parsedNotes: [AppleCloudNotesParsedNote]? = nil,
        parserThrows: Bool = false,
        exporterFailures: Set<String> = [],
        folders: [AppleNotesFolder] = SyncHarness.defaultFolders
    ) throws {
        directory = try TemporaryDirectory()
        database = try StateDatabase.open(at: directory.url.appendingPathComponent("state.sqlite"))
        let inventory = AppleNotesInventory(
            accounts: [AppleNotesAccount(objectID: 1, uuid: "account-uuid", name: "iCloud")],
            folders: folders,
            notes: notes
        )
        let inventoryReader = FakeSyncInventoryReader(inventory: inventory)
        parser = FakeSyncParser(
            notes: parsedNotes ?? notes.map { SyncEngineTests.parsed(uuid: $0.uuid) },
            shouldThrow: parserThrows
        )
        exporter = FakeSyncExporter(failures: exporterFailures)
        engine = SyncEngine(
            inventoryReader: inventoryReader,
            stateDatabase: database,
            parser: parser,
            exporter: exporter,
            now: { Date(timeIntervalSince1970: 100) },
            idGenerator: { "scan-id" }
        )
    }

    func request(dryRun: Bool = false) -> SyncRequest {
        SyncRequest(
            databaseURL: directory.url.appendingPathComponent("NoteStore.sqlite"),
            notesContainerURL: directory.url,
            scopeRequest: AppleNotesScopeRequest(accountName: "iCloud", folderPath: "Capture", recursive: true),
            parserOutputDirectory: directory.url.appendingPathComponent("parser-output", isDirectory: true),
            exportOptions: NoteExportOptions(outputDirectory: directory.url.appendingPathComponent("exports", isDirectory: true)),
            missingGraceCount: 3,
            dryRun: dryRun
        )
    }

    static let defaultFolders = [
        AppleNotesFolder(objectID: 10, uuid: "folder-uuid", name: "Capture", accountObjectID: 1, parentObjectID: nil),
    ]
}

private struct FakeSyncInventoryReader: AppleNotesInventoryReading {
    var inventory: AppleNotesInventory

    func readInventory(databaseURL: URL) throws -> AppleNotesInventory {
        inventory
    }
}

private final class FakeSyncParser: NoteParsing {
    private let notes: [AppleCloudNotesParsedNote]
    private let shouldThrow: Bool

    init(notes: [AppleCloudNotesParsedNote], shouldThrow: Bool) {
        self.notes = notes
        self.shouldThrow = shouldThrow
    }

    func parse(notesContainer: URL, noteUUIDs: [String]) throws -> AppleCloudNotesParserResult {
        if shouldThrow {
            throw AppleCloudNotesParserError.invalidJSON("fixture failure")
        }
        let requested = Set(noteUUIDs)
        let filtered = notes.filter { requested.isEmpty || requested.contains($0.uuid) }
        return AppleCloudNotesParserResult(
            outputDirectory: notesContainer,
            jsonPath: notesContainer.appendingPathComponent("all_notes_1.json"),
            notes: filtered,
            standardOutput: "",
            standardError: ""
        )
    }
}

private final class FakeSyncExporter: NoteExporting {
    private let failures: Set<String>
    private(set) var exportedUUIDs: [String] = []

    init(failures: Set<String>) {
        self.failures = failures
    }

    func export(document: NoteDocument, options: NoteExportOptions) throws -> NoteExportResult {
        exportedUUIDs.append(document.uuid)
        if failures.contains(document.uuid) {
            throw CocoaError(.fileWriteUnknown)
        }
        return NoteExportResult(
            pdfURL: options.outputDirectory.appendingPathComponent("\(document.uuid).pdf"),
            sidecarURL: options.outputDirectory.appendingPathComponent("\(document.uuid).json"),
            debugHTMLURL: nil,
            contentHash: "sha256:\(NoteDocumentHasher().contentHash(for: document))"
        )
    }
}
