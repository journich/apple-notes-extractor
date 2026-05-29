import Foundation
import SQLite3

enum SQLiteFixture {
    static func createAppleNotesLikeDatabase(at url: URL) throws {
        try createDatabase(
            at: url,
            sql: """
            CREATE TABLE ZICCLOUDSYNCINGOBJECT (
                Z_PK INTEGER PRIMARY KEY,
                Z_ENT INTEGER,
                ZIDENTIFIER TEXT,
                ZNAME TEXT,
                ZACCOUNTNAMEFORACCOUNTLISTSORTING TEXT,
                ZTITLE TEXT,
                ZTITLE1 TEXT,
                ZTITLE2 TEXT,
                ZSNIPPET TEXT,
                ZCREATIONDATE1 REAL,
                ZMODIFICATIONDATE1 REAL,
                ZACCOUNT7 INTEGER,
                ZACCOUNT8 INTEGER,
                ZOWNER INTEGER,
                ZPARENT INTEGER,
                ZFOLDER INTEGER,
                ZNOTEDATA INTEGER
            );

            CREATE TABLE ZICNOTEDATA (
                Z_PK INTEGER PRIMARY KEY,
                ZDATA BLOB
            );

            CREATE TABLE Z_PRIMARYKEY (
                Z_ENT INTEGER PRIMARY KEY,
                Z_NAME TEXT
            );

            INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME)
            VALUES
                (12, 'ICNote'),
                (14, 'ICAccount'),
                (15, 'ICFolder');

            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZNAME, ZACCOUNTNAMEFORACCOUNTLISTSORTING)
            VALUES (100, 14, 'fixture-account-uuid', 'iCloud', '1_iCloud');

            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE2, ZACCOUNT8, ZOWNER)
            VALUES
                (200, 15, 'fixture-folder-root-uuid', 'Capture', 100, 100),
                (201, 15, 'fixture-folder-child-uuid', 'Sketches', 100, 100);

            UPDATE ZICCLOUDSYNCINGOBJECT
            SET ZPARENT = 200
            WHERE Z_PK = 201;

            INSERT INTO ZICCLOUDSYNCINGOBJECT (
                Z_PK,
                Z_ENT,
                ZIDENTIFIER,
                ZTITLE1,
                ZSNIPPET,
                ZCREATIONDATE1,
                ZMODIFICATIONDATE1,
                ZACCOUNT7,
                ZFOLDER,
                ZNOTEDATA
            )
            VALUES
                (300, 12, 'fixture-note-uuid', 'Fixture note', 'Fixture snippet', 0, 60, 100, 200, 1),
                (301, 12, 'fixture-child-note-uuid', 'Nested fixture note', NULL, 0, 120, 100, 201, 2);

            INSERT INTO ZICNOTEDATA (Z_PK, ZDATA)
            VALUES
                (1, X'68656C6C6F206E6F746520626F6479'),
                (2, X'6E657374656420626F6479');
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
