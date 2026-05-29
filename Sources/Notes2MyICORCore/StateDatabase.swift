import Foundation
import SQLite3

public struct NoteState: Equatable, Sendable {
    public var noteUUID: String
    public var title: String?
    public var exportStatus: String
    public var pdfPath: String?
    public var contentHash: String?
    public var lastSeenAt: String

    public init(
        noteUUID: String,
        title: String? = nil,
        exportStatus: String = "pending",
        pdfPath: String? = nil,
        contentHash: String? = nil,
        lastSeenAt: String
    ) {
        self.noteUUID = noteUUID
        self.title = title
        self.exportStatus = exportStatus
        self.pdfPath = pdfPath
        self.contentHash = contentHash
        self.lastSeenAt = lastSeenAt
    }
}

public struct ScanRunState: Equatable, Sendable {
    public var scanID: String
    public var startedAt: String
    public var completedAt: String?
    public var status: String
    public var notesSeen: Int
    public var notesExported: Int
    public var notesFailed: Int

    public init(
        scanID: String,
        startedAt: String,
        completedAt: String? = nil,
        status: String,
        notesSeen: Int = 0,
        notesExported: Int = 0,
        notesFailed: Int = 0
    ) {
        self.scanID = scanID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
        self.notesSeen = notesSeen
        self.notesExported = notesExported
        self.notesFailed = notesFailed
    }
}

public struct SyncRootState: Equatable, Sendable {
    public var rootID: String
    public var accountName: String
    public var folderPath: String
    public var recursive: Bool
    public var createdAt: String

    public init(rootID: String, accountName: String, folderPath: String, recursive: Bool, createdAt: String) {
        self.rootID = rootID
        self.accountName = accountName
        self.folderPath = folderPath
        self.recursive = recursive
        self.createdAt = createdAt
    }
}

public struct StateDatabaseStatus: Equatable, Sendable {
    public var schemaVersion: Int
    public var notesCount: Int
    public var scanRunsCount: Int
    public var syncRootsCount: Int

    public init(schemaVersion: Int, notesCount: Int, scanRunsCount: Int, syncRootsCount: Int) {
        self.schemaVersion = schemaVersion
        self.notesCount = notesCount
        self.scanRunsCount = scanRunsCount
        self.syncRootsCount = syncRootsCount
    }
}

public enum StateDatabaseError: Error, Equatable, LocalizedError {
    case openFailed(String)
    case executeFailed(String)
    case queryFailed(String)
    case bindFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            "Failed to open state database: \(message)"
        case .executeFailed(let message):
            "Failed to update state database: \(message)"
        case .queryFailed(let message):
            "Failed to query state database: \(message)"
        case .bindFailed(let message):
            "Failed to bind state database value: \(message)"
        }
    }
}

public final class StateDatabase {
    public static let currentSchemaVersion = 1

    private let database: OpaquePointer

    private init(database: OpaquePointer) {
        self.database = database
    }

    deinit {
        sqlite3_close(database)
    }

    public static func open(at url: URL) throws -> StateDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var database: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)

        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite returned code \(result)"
            if let database {
                sqlite3_close(database)
            }
            throw StateDatabaseError.openFailed(message)
        }

        return StateDatabase(database: database)
    }

    public func migrate() throws {
        try execute("PRAGMA foreign_keys = ON;")
        try execute(
            """
            CREATE TABLE IF NOT EXISTS notes_state (
                note_uuid TEXT PRIMARY KEY,
                apple_object_pk INTEGER,
                account_name TEXT,
                account_uuid TEXT,
                folder_uuid TEXT,
                folder_path TEXT,
                folder_name TEXT,
                title TEXT,
                snippet TEXT,
                created_coredata REAL,
                modified_coredata REAL,
                created_at_utc TEXT,
                modified_at_utc TEXT,
                last_seen_at TEXT NOT NULL,
                last_exported_at TEXT,
                last_successful_scan_id TEXT,
                content_hash TEXT,
                metadata_hash TEXT,
                pdf_path TEXT,
                sidecar_json_path TEXT,
                export_status TEXT NOT NULL DEFAULT 'pending',
                export_error TEXT,
                is_deleted INTEGER NOT NULL DEFAULT 0,
                deleted_detected_at TEXT,
                is_in_scope INTEGER NOT NULL DEFAULT 1,
                out_of_scope_detected_at TEXT,
                missing_scan_count INTEGER NOT NULL DEFAULT 0,
                first_missing_at TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_notes_state_modified
            ON notes_state(modified_coredata);

            CREATE INDEX IF NOT EXISTS idx_notes_state_deleted
            ON notes_state(is_deleted);

            CREATE INDEX IF NOT EXISTS idx_notes_state_in_scope
            ON notes_state(is_in_scope);

            CREATE TABLE IF NOT EXISTS scan_runs (
                scan_id TEXT PRIMARY KEY,
                started_at TEXT NOT NULL,
                completed_at TEXT,
                status TEXT NOT NULL,
                notes_seen INTEGER DEFAULT 0,
                notes_new INTEGER DEFAULT 0,
                notes_modified INTEGER DEFAULT 0,
                notes_exported INTEGER DEFAULT 0,
                notes_failed INTEGER DEFAULT 0,
                notes_missing INTEGER DEFAULT 0,
                error TEXT
            );

            CREATE TABLE IF NOT EXISTS sync_roots (
                root_id TEXT PRIMARY KEY,
                account_name TEXT NOT NULL,
                account_uuid TEXT,
                folder_path TEXT NOT NULL,
                folder_uuid TEXT,
                recursive INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                last_resolved_at TEXT
            );
            """
        )
        try execute("PRAGMA user_version = \(Self.currentSchemaVersion);")
    }

    public func schemaVersion() throws -> Int {
        try query("PRAGMA user_version;").first?.int("user_version") ?? 0
    }

    public func status() throws -> StateDatabaseStatus {
        StateDatabaseStatus(
            schemaVersion: try schemaVersion(),
            notesCount: try count("notes_state"),
            scanRunsCount: try count("scan_runs"),
            syncRootsCount: try count("sync_roots")
        )
    }

    public func upsertNoteState(_ state: NoteState) throws {
        try executePrepared(
            """
            INSERT INTO notes_state (note_uuid, title, export_status, pdf_path, content_hash, last_seen_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(note_uuid) DO UPDATE SET
                title = excluded.title,
                export_status = excluded.export_status,
                pdf_path = excluded.pdf_path,
                content_hash = excluded.content_hash,
                last_seen_at = excluded.last_seen_at;
            """,
            bindings: [
                .text(state.noteUUID),
                .optionalText(state.title),
                .text(state.exportStatus),
                .optionalText(state.pdfPath),
                .optionalText(state.contentHash),
                .text(state.lastSeenAt),
            ]
        )
    }

    public func noteState(noteUUID: String) throws -> NoteState? {
        let rows = try queryPrepared(
            """
            SELECT note_uuid, title, export_status, pdf_path, content_hash, last_seen_at
            FROM notes_state
            WHERE note_uuid = ?;
            """,
            bindings: [.text(noteUUID)]
        )

        guard let row = rows.first else {
            return nil
        }

        return NoteState(
            noteUUID: row.string("note_uuid"),
            title: row.optionalString("title"),
            exportStatus: row.string("export_status"),
            pdfPath: row.optionalString("pdf_path"),
            contentHash: row.optionalString("content_hash"),
            lastSeenAt: row.string("last_seen_at")
        )
    }

    public func resetNoteState(noteUUID: String) throws {
        try executePrepared("DELETE FROM notes_state WHERE note_uuid = ?;", bindings: [.text(noteUUID)])
    }

    public func upsertScanRun(_ scanRun: ScanRunState) throws {
        try executePrepared(
            """
            INSERT INTO scan_runs (scan_id, started_at, completed_at, status, notes_seen, notes_exported, notes_failed)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(scan_id) DO UPDATE SET
                completed_at = excluded.completed_at,
                status = excluded.status,
                notes_seen = excluded.notes_seen,
                notes_exported = excluded.notes_exported,
                notes_failed = excluded.notes_failed;
            """,
            bindings: [
                .text(scanRun.scanID),
                .text(scanRun.startedAt),
                .optionalText(scanRun.completedAt),
                .text(scanRun.status),
                .int(scanRun.notesSeen),
                .int(scanRun.notesExported),
                .int(scanRun.notesFailed),
            ]
        )
    }

    public func upsertSyncRoot(_ syncRoot: SyncRootState) throws {
        try executePrepared(
            """
            INSERT INTO sync_roots (root_id, account_name, folder_path, recursive, created_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(root_id) DO UPDATE SET
                account_name = excluded.account_name,
                folder_path = excluded.folder_path,
                recursive = excluded.recursive;
            """,
            bindings: [
                .text(syncRoot.rootID),
                .text(syncRoot.accountName),
                .text(syncRoot.folderPath),
                .int(syncRoot.recursive ? 1 : 0),
                .text(syncRoot.createdAt),
            ]
        )
    }

    private func count(_ table: String) throws -> Int {
        try query("SELECT COUNT(*) AS count FROM \(table);").first?.int("count") ?? 0
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)

        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw StateDatabaseError.executeFailed(message)
        }
    }

    private func query(_ sql: String) throws -> [SQLiteRow] {
        try queryPrepared(sql, bindings: [])
    }

    private func executePrepared(_ sql: String, bindings: [SQLiteBinding]) throws {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)

        guard prepareResult == SQLITE_OK, let statement else {
            throw StateDatabaseError.executeFailed(String(cString: sqlite3_errmsg(database)))
        }

        defer {
            sqlite3_finalize(statement)
        }

        try bind(bindings, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StateDatabaseError.executeFailed(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func queryPrepared(_ sql: String, bindings: [SQLiteBinding]) throws -> [SQLiteRow] {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)

        guard prepareResult == SQLITE_OK, let statement else {
            throw StateDatabaseError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }

        defer {
            sqlite3_finalize(statement)
        }

        try bind(bindings, to: statement)

        var rows: [SQLiteRow] = []
        let columnCount = sqlite3_column_count(statement)

        while true {
            let stepResult = sqlite3_step(statement)

            switch stepResult {
            case SQLITE_ROW:
                var values: [String: SQLiteValue] = [:]

                for index in 0..<columnCount {
                    guard let namePointer = sqlite3_column_name(statement, index) else {
                        continue
                    }

                    let name = String(cString: namePointer)
                    values[name] = SQLiteValue(statement: statement, index: index)
                }

                rows.append(SQLiteRow(values: values))
            case SQLITE_DONE:
                return rows
            default:
                throw StateDatabaseError.queryFailed(String(cString: sqlite3_errmsg(database)))
            }
        }
    }

    private func bind(_ bindings: [SQLiteBinding], to statement: OpaquePointer) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32

            switch binding {
            case .null:
                result = sqlite3_bind_null(statement, index)
            case .text(let value):
                result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            case .int(let value):
                result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
            }

            guard result == SQLITE_OK else {
                throw StateDatabaseError.bindFailed(String(cString: sqlite3_errmsg(database)))
            }
        }
    }
}

private enum SQLiteBinding {
    case null
    case text(String)
    case int(Int)

    static func optionalText(_ value: String?) -> SQLiteBinding {
        value.map(SQLiteBinding.text) ?? .null
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
