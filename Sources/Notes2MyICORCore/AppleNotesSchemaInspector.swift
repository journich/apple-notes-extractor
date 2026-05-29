import Foundation

public struct AppleNotesSchemaInspection: Equatable, Sendable {
    public var databasePath: String
    public var readOnlyURI: String
    public var tables: [SQLiteTable]
    public var keyTables: [String: SQLiteTable]

    public init(databasePath: String, readOnlyURI: String, tables: [SQLiteTable], keyTables: [String: SQLiteTable]) {
        self.databasePath = databasePath
        self.readOnlyURI = readOnlyURI
        self.tables = tables
        self.keyTables = keyTables
    }
}

public struct SQLiteTable: Equatable, Sendable {
    public var name: String
    public var sql: String?
    public var columns: [SQLiteColumn]

    public init(name: String, sql: String?, columns: [SQLiteColumn] = []) {
        self.name = name
        self.sql = sql
        self.columns = columns
    }
}

public struct SQLiteColumn: Equatable, Sendable {
    public var cid: Int
    public var name: String
    public var type: String
    public var notNull: Bool
    public var defaultValue: String?
    public var primaryKeyPosition: Int

    public init(
        cid: Int,
        name: String,
        type: String,
        notNull: Bool,
        defaultValue: String?,
        primaryKeyPosition: Int
    ) {
        self.cid = cid
        self.name = name
        self.type = type
        self.notNull = notNull
        self.defaultValue = defaultValue
        self.primaryKeyPosition = primaryKeyPosition
    }
}

public enum AppleNotesStoreError: Error, Equatable, LocalizedError {
    case databaseNotFound(String)
    case databaseNotReadable(String)
    case sqliteOpenFailed(String)
    case sqliteQueryFailed(String)

    public var errorDescription: String? {
        switch self {
        case .databaseNotFound(let path):
            "Apple Notes database not found at \(path)"
        case .databaseNotReadable(let path):
            "Apple Notes database is not readable at \(path). Full Disk Access may be required."
        case .sqliteOpenFailed(let message):
            "Failed to open Apple Notes database read-only: \(message)"
        case .sqliteQueryFailed(let message):
            "Failed to inspect Apple Notes schema: \(message)"
        }
    }
}

public struct AppleNotesSchemaInspector {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func inspect(databaseURL: URL) throws -> AppleNotesSchemaInspection {
        let path = databaseURL.path
        guard fileManager.fileExists(atPath: path) else {
            throw AppleNotesStoreError.databaseNotFound(path)
        }

        guard fileManager.isReadableFile(atPath: path) else {
            throw AppleNotesStoreError.databaseNotReadable(path)
        }

        let connection = try SQLiteReadOnlyConnection.open(databaseURL: databaseURL)
        try connection.execute("PRAGMA query_only = ON;")

        let tableRows = try connection.query(
            """
            SELECT name, sql
            FROM sqlite_master
            WHERE type = 'table'
            ORDER BY name;
            """
        )

        let tables = try tableRows.map { row in
            let name = row.string("name")
            return SQLiteTable(
                name: name,
                sql: row.optionalString("sql"),
                columns: try loadColumns(tableName: name, connection: connection)
            )
        }

        let keyTables = Dictionary(uniqueKeysWithValues: tables
            .filter { ["ZICCLOUDSYNCINGOBJECT", "ZICNOTEDATA"].contains($0.name) }
            .map { ($0.name, $0) })

        return AppleNotesSchemaInspection(
            databasePath: path,
            readOnlyURI: SQLiteReadOnlyConnection.readOnlyURI(for: databaseURL),
            tables: tables,
            keyTables: keyTables
        )
    }

    private func loadColumns(tableName: String, connection: SQLiteReadOnlyConnection) throws -> [SQLiteColumn] {
        let quotedTable = SQLiteIdentifier(tableName).quoted
        let rows = try connection.query("PRAGMA table_info(\(quotedTable));")

        return rows.map { row in
            SQLiteColumn(
                cid: row.int("cid"),
                name: row.string("name"),
                type: row.string("type"),
                notNull: row.int("notnull") != 0,
                defaultValue: row.optionalString("dflt_value"),
                primaryKeyPosition: row.int("pk")
            )
        }
    }
}

public struct SchemaInspectionFormatter {
    public init() {}

    public func format(_ inspection: AppleNotesSchemaInspection) -> String {
        var lines: [String] = []
        lines.append("Apple Notes schema inspection")
        lines.append("Database: \(inspection.databasePath)")
        lines.append("Read-only URI: \(inspection.readOnlyURI)")
        lines.append("Tables: \(inspection.tables.count)")
        lines.append("")

        if inspection.keyTables.isEmpty {
            lines.append("Key tables: missing ZICCLOUDSYNCINGOBJECT and ZICNOTEDATA")
        } else {
            lines.append("Key tables:")
            for name in ["ZICCLOUDSYNCINGOBJECT", "ZICNOTEDATA"] {
                if let table = inspection.keyTables[name] {
                    lines.append("  - \(table.name) (\(table.columns.count) columns)")
                } else {
                    lines.append("  - \(name) missing")
                }
            }
        }

        lines.append("")
        lines.append("Table details:")
        for table in inspection.tables {
            lines.append("- \(table.name)")
            for column in table.columns {
                let type = column.type.isEmpty ? "UNKNOWN" : column.type
                lines.append("    \(column.name) \(type)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

private struct SQLiteIdentifier {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    var quoted: String {
        "\"\(rawValue.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
