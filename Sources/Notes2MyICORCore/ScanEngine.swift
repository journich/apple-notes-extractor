import Foundation

public struct ScanEngine {
    public let inventoryReader: AppleNotesInventoryReader
    public let stateDatabase: StateDatabase
    public let now: @Sendable () -> Date

    public init(
        inventoryReader: AppleNotesInventoryReader = AppleNotesInventoryReader(),
        stateDatabase: StateDatabase,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.inventoryReader = inventoryReader
        self.stateDatabase = stateDatabase
        self.now = now
    }

    public func scan(databaseURL: URL, scopeRequest: AppleNotesScopeRequest, missingGraceCount: Int) throws -> ChangeSummary {
        try stateDatabase.migrate()

        let inventory = try inventoryReader.readInventory(databaseURL: databaseURL)
        let scope = try AppleNotesScopeResolver().resolve(scopeRequest, inventory: inventory)
        let inScopeNotes = inventory.notes.filter { note in
            guard let folderID = note.folderObjectID else {
                return false
            }
            return scope.allowedFolderIDs.contains(folderID)
        }
        let previousStates = try stateDatabase.loadAllNoteStates()

        let summary = ChangeClassifier().classify(
            inScopeNotes: inScopeNotes,
            allCurrentNotes: inventory.notes,
            previousStates: previousStates,
            allowedFolderIDs: scope.allowedFolderIDs,
            folders: inventory.folders,
            missingGraceCount: missingGraceCount
        )

        let scanID = UUID().uuidString
        let timestamp = ISO8601DateFormatter().string(from: now())
        try stateDatabase.upsertScanRun(ScanRunState(
            scanID: scanID,
            startedAt: timestamp,
            completedAt: timestamp,
            status: "success",
            notesSeen: inScopeNotes.count
        ))

        for change in summary.changes {
            try updateState(for: change, timestamp: timestamp)
        }

        return summary
    }

    private func updateState(for change: NoteChange, timestamp: String) throws {
        switch change.kind {
        case .new, .modified, .metadataChanged, .unchanged, .exportFailed:
            guard let note = change.note else {
                return
            }
            try stateDatabase.upsertNoteState(NoteState(
                noteUUID: note.uuid,
                title: note.title,
                exportStatus: change.previousState?.exportStatus ?? "pending",
                pdfPath: change.previousState?.pdfPath,
                contentHash: change.previousState?.contentHash,
                modifiedCoreData: note.modifiedCoreData,
                folderPath: note.folderObjectID.map(String.init),
                missingScanCount: 0,
                isDeleted: false,
                isInScope: true,
                lastSeenAt: timestamp,
                deletedDetectedAt: change.previousState?.deletedDetectedAt,
                firstMissingAt: change.previousState?.firstMissingAt
            ))
        case .outOfScope, .recentlyDeleted:
            guard let previous = change.previousState else {
                return
            }
            try stateDatabase.upsertNoteState(NoteState(
                noteUUID: previous.noteUUID,
                title: previous.title,
                exportStatus: change.kind == .recentlyDeleted ? "soft_deleted" : "out_of_scope",
                pdfPath: previous.pdfPath,
                contentHash: previous.contentHash,
                modifiedCoreData: previous.modifiedCoreData,
                folderPath: previous.folderPath,
                missingScanCount: 0,
                isDeleted: change.kind == .recentlyDeleted,
                isInScope: false,
                lastSeenAt: timestamp,
                deletedDetectedAt: change.kind == .recentlyDeleted ? previous.deletedDetectedAt ?? timestamp : previous.deletedDetectedAt,
                firstMissingAt: previous.firstMissingAt
            ))
        case .missingPossiblyDeleted, .deletedAfterGrace:
            guard let previous = change.previousState else {
                return
            }
            try stateDatabase.upsertNoteState(NoteState(
                noteUUID: previous.noteUUID,
                title: previous.title,
                exportStatus: previous.exportStatus,
                pdfPath: previous.pdfPath,
                contentHash: previous.contentHash,
                modifiedCoreData: previous.modifiedCoreData,
                folderPath: previous.folderPath,
                missingScanCount: previous.missingScanCount + 1,
                isDeleted: change.kind == .deletedAfterGrace,
                isInScope: previous.isInScope,
                lastSeenAt: previous.lastSeenAt,
                deletedDetectedAt: change.kind == .deletedAfterGrace ? previous.deletedDetectedAt ?? timestamp : previous.deletedDetectedAt,
                firstMissingAt: previous.firstMissingAt ?? timestamp
            ))
        }
    }
}
