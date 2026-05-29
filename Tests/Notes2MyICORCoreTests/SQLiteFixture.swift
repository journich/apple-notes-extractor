import Foundation
import SQLite3

enum SQLiteFixture {
    static func createAppleNotesLikeDatabase(at url: URL) throws {
        try createDatabase(
            at: url,
            sql: """
            CREATE TABLE ZICCLOUDSYNCINGOBJECT (
                Z_PK INTEGER PRIMARY KEY,
                ZIDENTIFIER TEXT,
                ZTITLE1 TEXT,
                ZNOTEDATA INTEGER
            );

            CREATE TABLE ZICNOTEDATA (
                Z_PK INTEGER PRIMARY KEY,
                ZDATA BLOB
            );

            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER, ZTITLE1, ZNOTEDATA)
            VALUES (1, 'fixture-note-uuid', 'Fixture note', 1);

            INSERT INTO ZICNOTEDATA (Z_PK, ZDATA)
            VALUES (1, X'68656C6C6F206E6F746520626F6479');
            """
        )
    }

    static func createDatabase(at url: URL, sql: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var database: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil)

        guard result == SQLITE_OK, let database else {
            throw FixtureError.openFailed
        }

        defer {
            sqlite3_close(database)
        }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let execResult = sqlite3_exec(database, sql, nil, nil, &errorMessage)

        guard execResult == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown SQLite fixture error"
            sqlite3_free(errorMessage)
            throw FixtureError.execFailed(message)
        }
    }
}

enum FixtureError: Error {
    case openFailed
    case execFailed(String)
}
