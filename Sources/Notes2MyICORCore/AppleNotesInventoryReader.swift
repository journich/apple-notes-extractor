import Foundation

public protocol AppleNotesInventoryReading {
    func readInventory(databaseURL: URL) throws -> AppleNotesInventory
}

public struct AppleNotesInventoryReader {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func readInventory(databaseURL: URL) throws -> AppleNotesInventory {
        let path = databaseURL.path
        guard fileManager.fileExists(atPath: path) else {
            throw AppleNotesStoreError.databaseNotFound(path)
        }

        guard fileManager.isReadableFile(atPath: path) else {
            throw AppleNotesStoreError.databaseNotReadable(path)
        }

        let connection = try SQLiteReadOnlyConnection.open(databaseURL: databaseURL)
        try connection.execute("PRAGMA query_only = ON;")

        let entities = try readEntityMap(connection: connection)
        let accountEntity = try entities.require("ICAccount")
        let folderEntity = try entities.require("ICFolder")
        let noteEntity = try entities.require("ICNote")

        let accounts = try readAccounts(connection: connection, entityID: accountEntity)
        let folders = try readFolders(connection: connection, entityID: folderEntity)
        let notes = try readNotes(connection: connection, entityID: noteEntity)

        return AppleNotesInventory(accounts: accounts, folders: folders, notes: notes)
    }

    private func readEntityMap(connection: SQLiteReadOnlyConnection) throws -> [String: Int] {
        let rows = try connection.query("SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY;")
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.string("Z_NAME"), $0.int("Z_ENT")) })
    }

    private func readAccounts(connection: SQLiteReadOnlyConnection, entityID: Int) throws -> [AppleNotesAccount] {
        let rows = try connection.query(
            """
            SELECT
                Z_PK,
                ZIDENTIFIER,
                COALESCE(ZNAME, ZACCOUNTNAMEFORACCOUNTLISTSORTING, ZTITLE2, ZTITLE1, '') AS DISPLAY_NAME
            FROM ZICCLOUDSYNCINGOBJECT
            WHERE Z_ENT = \(entityID)
            ORDER BY DISPLAY_NAME, Z_PK;
            """
        )

        return rows.map { row in
            AppleNotesAccount(
                objectID: row.int("Z_PK"),
                uuid: row.string("ZIDENTIFIER"),
                name: normalizedAccountName(row.string("DISPLAY_NAME"))
            )
        }
    }

    private func readFolders(connection: SQLiteReadOnlyConnection, entityID: Int) throws -> [AppleNotesFolder] {
        let rows = try connection.query(
            """
            SELECT
                Z_PK,
                ZIDENTIFIER,
                COALESCE(ZTITLE2, ZTITLE1, ZNAME, '') AS DISPLAY_NAME,
                ZACCOUNT8,
                ZOWNER,
                ZPARENT
            FROM ZICCLOUDSYNCINGOBJECT
            WHERE Z_ENT = \(entityID)
            ORDER BY DISPLAY_NAME, Z_PK;
            """
        )

        return rows.map { row in
            AppleNotesFolder(
                objectID: row.int("Z_PK"),
                uuid: row.string("ZIDENTIFIER"),
                name: row.string("DISPLAY_NAME"),
                accountObjectID: row.optionalInt("ZACCOUNT8") ?? row.optionalInt("ZOWNER"),
                parentObjectID: row.optionalInt("ZPARENT")
            )
        }
    }

    private func readNotes(connection: SQLiteReadOnlyConnection, entityID: Int) throws -> [AppleNotesNoteMetadata] {
        let rows = try connection.query(
            """
            SELECT
                Z_PK,
                ZIDENTIFIER,
                COALESCE(ZTITLE1, ZTITLE, '') AS DISPLAY_TITLE,
                ZSNIPPET,
                ZCREATIONDATE1,
                ZMODIFICATIONDATE1,
                ZACCOUNT7,
                ZFOLDER,
                ZNOTEDATA
            FROM ZICCLOUDSYNCINGOBJECT
            WHERE Z_ENT = \(entityID)
              AND ZNOTEDATA IS NOT NULL
              AND ZIDENTIFIER IS NOT NULL
            ORDER BY ZMODIFICATIONDATE1 DESC, Z_PK;
            """
        )

        return rows.map { row in
            let createdCoreData = row.optionalDouble("ZCREATIONDATE1")
            let modifiedCoreData = row.optionalDouble("ZMODIFICATIONDATE1")

            return AppleNotesNoteMetadata(
                objectID: row.int("Z_PK"),
                uuid: row.string("ZIDENTIFIER"),
                title: row.string("DISPLAY_TITLE"),
                snippet: row.optionalString("ZSNIPPET"),
                createdCoreData: createdCoreData,
                modifiedCoreData: modifiedCoreData,
                createdAt: CoreDataTimestamp.date(fromCoreDataTimestamp: createdCoreData),
                modifiedAt: CoreDataTimestamp.date(fromCoreDataTimestamp: modifiedCoreData),
                accountObjectID: row.optionalInt("ZACCOUNT7"),
                folderObjectID: row.optionalInt("ZFOLDER"),
                noteDataObjectID: row.optionalInt("ZNOTEDATA")
            )
        }
    }

    private func normalizedAccountName(_ rawName: String) -> String {
        if rawName.hasPrefix("1_") {
            return String(rawName.dropFirst(2))
        }
        return rawName
    }
}

extension AppleNotesInventoryReader: AppleNotesInventoryReading {}

public enum AppleNotesInventoryError: Error, Equatable, LocalizedError {
    case missingEntity(String)
    case accountNotFound(String)
    case folderNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .missingEntity(let name):
            "Apple Notes schema is missing expected entity: \(name)"
        case .accountNotFound(let name):
            "Apple Notes account not found: \(name)"
        case .folderNotFound(let path):
            "Apple Notes folder not found: \(path)"
        }
    }
}

private extension Dictionary where Key == String, Value == Int {
    func require(_ key: String) throws -> Int {
        guard let value = self[key] else {
            throw AppleNotesInventoryError.missingEntity(key)
        }
        return value
    }
}
