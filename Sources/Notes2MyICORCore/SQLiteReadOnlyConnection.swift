import Foundation
import SQLite3

public final class SQLiteReadOnlyConnection {
    private let database: OpaquePointer

    private init(database: OpaquePointer) {
        self.database = database
    }

    deinit {
        sqlite3_close(database)
    }

    public static func readOnlyURI(for databaseURL: URL) -> String {
        let path = databaseURL.standardizedFileURL.path
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#"))
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
        return "file:\(encodedPath)?mode=ro"
    }

    public static func open(databaseURL: URL) throws -> SQLiteReadOnlyConnection {
        let uri = readOnlyURI(for: databaseURL)
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        let result = sqlite3_open_v2(uri, &database, flags, nil)

        guard result == SQLITE_OK, let database else {
            let message: String
            if let database {
                message = String(cString: sqlite3_errmsg(database))
                sqlite3_close(database)
            } else {
                message = "SQLite returned code \(result)"
            }
            throw AppleNotesStoreError.sqliteOpenFailed(message)
        }

        return SQLiteReadOnlyConnection(database: database)
    }

    public func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)

        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw AppleNotesStoreError.sqliteQueryFailed(message)
        }
    }

    public func query(_ sql: String) throws -> [SQLiteRow] {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)

        guard prepareResult == SQLITE_OK, let statement else {
            throw AppleNotesStoreError.sqliteQueryFailed(String(cString: sqlite3_errmsg(database)))
        }

        defer {
            sqlite3_finalize(statement)
        }

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
                throw AppleNotesStoreError.sqliteQueryFailed(String(cString: sqlite3_errmsg(database)))
            }
        }
    }
}

public struct SQLiteRow: Equatable, Sendable {
    public let values: [String: SQLiteValue]

    public init(values: [String: SQLiteValue]) {
        self.values = values
    }

    public func string(_ name: String) -> String {
        optionalString(name) ?? ""
    }

    public func optionalString(_ name: String) -> String? {
        guard let value = values[name] else {
            return nil
        }

        switch value {
        case .null:
            return nil
        case .integer(let int):
            return String(int)
        case .real(let double):
            return String(double)
        case .text(let string):
            return string
        case .blob:
            return "<blob>"
        }
    }

    public func int(_ name: String) -> Int {
        guard let value = values[name] else {
            return 0
        }

        switch value {
        case .integer(let int):
            return int
        case .real(let double):
            return Int(double)
        case .text(let string):
            return Int(string) ?? 0
        case .null, .blob:
            return 0
        }
    }
}

public enum SQLiteValue: Equatable, Sendable {
    case null
    case integer(Int)
    case real(Double)
    case text(String)
    case blob(Data)

    init(statement: OpaquePointer, index: Int32) {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_NULL:
            self = .null
        case SQLITE_INTEGER:
            self = .integer(Int(sqlite3_column_int64(statement, index)))
        case SQLITE_FLOAT:
            self = .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            if let text = sqlite3_column_text(statement, index) {
                self = .text(String(cString: text))
            } else {
                self = .null
            }
        case SQLITE_BLOB:
            let byteCount = Int(sqlite3_column_bytes(statement, index))
            if let bytes = sqlite3_column_blob(statement, index), byteCount > 0 {
                self = .blob(Data(bytes: bytes, count: byteCount))
            } else {
                self = .blob(Data())
            }
        default:
            self = .null
        }
    }
}
