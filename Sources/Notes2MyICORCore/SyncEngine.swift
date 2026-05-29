import Foundation

public struct SyncRequest: Equatable, Sendable {
    public var databaseURL: URL
    public var notesContainerURL: URL
    public var scopeRequest: AppleNotesScopeRequest
    public var parserOutputDirectory: URL
    public var exportOptions: NoteExportOptions
    public var missingGraceCount: Int
    public var dryRun: Bool

    public init(
        databaseURL: URL,
        notesContainerURL: URL,
        scopeRequest: AppleNotesScopeRequest,
        parserOutputDirectory: URL,
        exportOptions: NoteExportOptions,
        missingGraceCount: Int,
        dryRun: Bool = false
    ) {
        self.databaseURL = databaseURL
        self.notesContainerURL = notesContainerURL
        self.scopeRequest = scopeRequest
        self.parserOutputDirectory = parserOutputDirectory
        self.exportOptions = exportOptions
        self.missingGraceCount = missingGraceCount
        self.dryRun = dryRun
    }
}

public struct SyncSummary: Equatable, Sendable {
    public var changeSummary: ChangeSummary
    public var exported: Int
    public var failed: Int
    public var skippedUnchanged: Int
    public var skippedContentUnchanged: Int
    public var dryRun: Bool

    public init(
        changeSummary: ChangeSummary,
        exported: Int = 0,
        failed: Int = 0,
        skippedUnchanged: Int = 0,
        skippedContentUnchanged: Int = 0,
        dryRun: Bool = false
    ) {
        self.changeSummary = changeSummary
        self.exported = exported
        self.failed = failed
        self.skippedUnchanged = skippedUnchanged
        self.skippedContentUnchanged = skippedContentUnchanged
        self.dryRun = dryRun
    }
}

public struct SyncEngine {
    public let inventoryReader: any AppleNotesInventoryReading
    public let stateDatabase: StateDatabase
    public let parser: any NoteParsing
    public let exporter: any NoteExporting
    public let now: @Sendable () -> Date
    public let idGenerator: @Sendable () -> String

    public init(
        inventoryReader: any AppleNotesInventoryReading = AppleNotesInventoryReader(),
        stateDatabase: StateDatabase,
        parser: any NoteParsing,
        exporter: any NoteExporting,
        now: @escaping @Sendable () -> Date = { Date() },
        idGenerator: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.inventoryReader = inventoryReader
        self.stateDatabase = stateDatabase
        self.parser = parser
        self.exporter = exporter
        self.now = now
        self.idGenerator = idGenerator
    }

    public func syncOnce(_ request: SyncRequest) throws -> SyncSummary {
        try stateDatabase.migrate()

        let startedAt = timestamp()
        let scanID = idGenerator()
        if request.dryRun == false {
            try stateDatabase.upsertScanRun(ScanRunState(
                scanID: scanID,
                startedAt: startedAt,
                status: "running"
            ))
        }

        let inventory = try inventoryReader.readInventory(databaseURL: request.databaseURL)
        let scope = try AppleNotesScopeResolver().resolve(request.scopeRequest, inventory: inventory)
        let inScopeNotes = inventory.notes.filter { note in
            guard let folderID = note.folderObjectID else {
                return false
            }
            return scope.allowedFolderIDs.contains(folderID)
        }
        let previousStates = try stateDatabase.loadAllNoteStates()
        let changeSummary = ChangeClassifier().classify(
            inScopeNotes: inScopeNotes,
            allCurrentNotes: inventory.notes,
            previousStates: previousStates,
            allowedFolderIDs: scope.allowedFolderIDs,
            missingGraceCount: request.missingGraceCount
        )

        var summary = SyncSummary(
            changeSummary: changeSummary,
            skippedUnchanged: changeSummary.count(.unchanged),
            dryRun: request.dryRun
        )
        let exportCandidates = changeSummary.changes.filter { change in
            [.new, .modified, .metadataChanged, .exportFailed].contains(change.kind)
        }

        guard request.dryRun == false else {
            return summary
        }

        let folderPaths = FolderPathBuilder(folders: inventory.folders).pathsByFolderID()
        let accountsByID = Dictionary(uniqueKeysWithValues: inventory.accounts.map { ($0.objectID, $0) })
        let exportUUIDs = exportCandidates.map(\.noteUUID)
        let parsedNotesByUUID: [String: AppleCloudNotesParsedNote]

        if exportUUIDs.isEmpty {
            parsedNotesByUUID = [:]
        } else {
            do {
                let parserResult = try parser.parse(notesContainer: request.notesContainerURL, noteUUIDs: exportUUIDs)
                parsedNotesByUUID = Dictionary(uniqueKeysWithValues: parserResult.notes.map { ($0.uuid, $0) })
            } catch {
                for change in exportCandidates {
                    if let note = change.note {
                        try markFailure(change: change, note: note, timestamp: startedAt)
                    }
                }
                summary.failed = exportCandidates.count
                try finishScanRun(scanID: scanID, startedAt: startedAt, notesSeen: inScopeNotes.count, summary: summary)
                return summary
            }
        }

        for change in changeSummary.changes {
            switch change.kind {
            case .unchanged:
                try preserveState(change: change, timestamp: startedAt)
            case .outOfScope, .missingPossiblyDeleted, .deletedAfterGrace:
                try updateNonExportState(change: change, timestamp: startedAt)
            case .new, .modified, .metadataChanged, .exportFailed:
                guard let note = change.note else {
                    continue
                }
                guard let parsed = parsedNotesByUUID[change.noteUUID] else {
                    try markFailure(change: change, note: note, timestamp: startedAt)
                    summary.failed += 1
                    continue
                }

                let document = NoteDocumentBuilder().document(
                    parsedNote: parsed,
                    metadata: note,
                    accountName: note.accountObjectID.flatMap { accountsByID[$0]?.name },
                    folderPath: note.folderObjectID.flatMap { folderPaths[$0] }
                )
                let contentHash = "sha256:\(NoteDocumentHasher().contentHash(for: document))"
                if change.previousState?.contentHash == contentHash,
                   change.previousState?.pdfPath != nil {
                    try markSuccess(
                        change: change,
                        note: note,
                        result: nil,
                        contentHash: contentHash,
                        timestamp: startedAt
                    )
                    summary.skippedContentUnchanged += 1
                    continue
                }

                do {
                    let result = try exporter.export(document: document, options: request.exportOptions)
                    try markSuccess(
                        change: change,
                        note: note,
                        result: result,
                        contentHash: result.contentHash,
                        timestamp: startedAt
                    )
                    summary.exported += 1
                } catch {
                    try markFailure(change: change, note: note, timestamp: startedAt)
                    summary.failed += 1
                }
            }
        }

        try finishScanRun(scanID: scanID, startedAt: startedAt, notesSeen: inScopeNotes.count, summary: summary)
        return summary
    }

    private func finishScanRun(scanID: String, startedAt: String, notesSeen: Int, summary: SyncSummary) throws {
        try stateDatabase.upsertScanRun(ScanRunState(
            scanID: scanID,
            startedAt: startedAt,
            completedAt: timestamp(),
            status: summary.failed > 0 ? "completed_with_failures" : "success",
            notesSeen: notesSeen,
            notesExported: summary.exported,
            notesFailed: summary.failed
        ))
    }

    private func markSuccess(
        change: NoteChange,
        note: AppleNotesNoteMetadata,
        result: NoteExportResult?,
        contentHash: String,
        timestamp: String
    ) throws {
        try stateDatabase.upsertNoteState(NoteState(
            noteUUID: note.uuid,
            title: note.title,
            exportStatus: "exported",
            pdfPath: result?.pdfURL.path ?? change.previousState?.pdfPath,
            contentHash: contentHash,
            modifiedCoreData: note.modifiedCoreData,
            folderPath: note.folderObjectID.map(String.init),
            missingScanCount: 0,
            isDeleted: false,
            isInScope: true,
            lastSeenAt: timestamp
        ))
    }

    private func markFailure(change: NoteChange, note: AppleNotesNoteMetadata, timestamp: String) throws {
        try stateDatabase.upsertNoteState(NoteState(
            noteUUID: note.uuid,
            title: note.title,
            exportStatus: "failed",
            pdfPath: change.previousState?.pdfPath,
            contentHash: change.previousState?.contentHash,
            modifiedCoreData: note.modifiedCoreData,
            folderPath: note.folderObjectID.map(String.init),
            missingScanCount: 0,
            isDeleted: false,
            isInScope: true,
            lastSeenAt: timestamp
        ))
    }

    private func preserveState(change: NoteChange, timestamp: String) throws {
        guard let note = change.note, let previous = change.previousState else {
            return
        }
        try stateDatabase.upsertNoteState(NoteState(
            noteUUID: note.uuid,
            title: note.title,
            exportStatus: previous.exportStatus,
            pdfPath: previous.pdfPath,
            contentHash: previous.contentHash,
            modifiedCoreData: note.modifiedCoreData,
            folderPath: previous.folderPath,
            missingScanCount: 0,
            isDeleted: false,
            isInScope: true,
            lastSeenAt: timestamp
        ))
    }

    private func updateNonExportState(change: NoteChange, timestamp: String) throws {
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
            missingScanCount: change.kind == .missingPossiblyDeleted || change.kind == .deletedAfterGrace
                ? previous.missingScanCount + 1
                : 0,
            isDeleted: change.kind == .deletedAfterGrace,
            isInScope: change.kind != .outOfScope,
            lastSeenAt: timestamp
        ))
    }

    private func timestamp() -> String {
        ISO8601DateFormatter().string(from: now())
    }
}

public struct SyncSummaryFormatter {
    public init() {}

    public func format(_ summary: SyncSummary) -> String {
        """
        Sync summary:
        DRY_RUN: \(summary.dryRun ? "true" : "false")
        NEW: \(summary.changeSummary.count(.new))
        MODIFIED: \(summary.changeSummary.count(.modified))
        METADATA_CHANGED: \(summary.changeSummary.count(.metadataChanged))
        UNCHANGED: \(summary.changeSummary.count(.unchanged))
        EXPORTED: \(summary.exported)
        SKIPPED_CONTENT_UNCHANGED: \(summary.skippedContentUnchanged)
        FAILED: \(summary.failed)
        """
    }
}
