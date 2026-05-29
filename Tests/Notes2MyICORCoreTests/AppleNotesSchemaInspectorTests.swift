import Foundation
import XCTest
@testable import Notes2MyICORCore

final class AppleNotesSchemaInspectorTests: XCTestCase {
    func testDefaultAppleNotesDatabasePath() {
        let paths = AppPaths(environment: ["HOME": "/tmp/example-home"])
        let appleNotesPaths = AppleNotesPaths(paths: paths)

        XCTAssertEqual(
            appleNotesPaths.noteStoreDatabaseURL.path,
            "/tmp/example-home/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"
        )
    }

    func testReadOnlyURIEncodesDatabasePath() {
        let url = URL(fileURLWithPath: "/tmp/example path/NoteStore.sqlite")

        XCTAssertEqual(
            SQLiteReadOnlyConnection.readOnlyURI(for: url),
            "file:/tmp/example%20path/NoteStore.sqlite?mode=ro"
        )
    }

    func testMissingDatabaseReportsClearError() throws {
        let directory = try TemporaryDirectory()
        let databaseURL = directory.url.appendingPathComponent("missing.sqlite")

        do {
            _ = try AppleNotesSchemaInspector().inspect(databaseURL: databaseURL)
            XCTFail("Expected missing database error")
        } catch let error as AppleNotesStoreError {
            XCTAssertTrue(error.errorDescription?.contains("database not found") == true)
        }
    }

    func testSchemaInspectorParsesFixtureDatabase() throws {
        let directory = try TemporaryDirectory()
        let databaseURL = directory.url.appendingPathComponent("NoteStore.sqlite")
        try SQLiteFixture.createAppleNotesLikeDatabase(at: databaseURL)

        let inspection = try AppleNotesSchemaInspector().inspect(databaseURL: databaseURL)

        XCTAssertEqual(inspection.databasePath, databaseURL.path)
        XCTAssertTrue(inspection.readOnlyURI.hasPrefix("file:"))
        XCTAssertTrue(inspection.tables.contains { $0.name == "ZICCLOUDSYNCINGOBJECT" })
        XCTAssertTrue(inspection.tables.contains { $0.name == "ZICNOTEDATA" })
        XCTAssertEqual(inspection.keyTables["ZICCLOUDSYNCINGOBJECT"]?.columns.map(\.name), [
            "Z_PK",
            "ZIDENTIFIER",
            "ZTITLE1",
            "ZNOTEDATA",
        ])
        XCTAssertEqual(inspection.keyTables["ZICNOTEDATA"]?.columns.map(\.name), [
            "Z_PK",
            "ZDATA",
        ])
    }

    func testSchemaInspectorHandlesMissingKeyTablesGracefully() throws {
        let directory = try TemporaryDirectory()
        let databaseURL = directory.url.appendingPathComponent("Other.sqlite")
        try SQLiteFixture.createDatabase(
            at: databaseURL,
            sql: "CREATE TABLE OTHER_TABLE (id INTEGER PRIMARY KEY, value TEXT);"
        )

        let inspection = try AppleNotesSchemaInspector().inspect(databaseURL: databaseURL)

        XCTAssertEqual(inspection.tables.map(\.name), ["OTHER_TABLE"])
        XCTAssertTrue(inspection.keyTables.isEmpty)

        let formatted = SchemaInspectionFormatter().format(inspection)
        XCTAssertTrue(formatted.contains("missing ZICCLOUDSYNCINGOBJECT and ZICNOTEDATA"))
    }

    func testReadOnlyConnectionRejectsWrites() throws {
        let directory = try TemporaryDirectory()
        let databaseURL = directory.url.appendingPathComponent("NoteStore.sqlite")
        try SQLiteFixture.createAppleNotesLikeDatabase(at: databaseURL)

        let connection = try SQLiteReadOnlyConnection.open(databaseURL: databaseURL)
        try connection.execute("PRAGMA query_only = ON;")

        do {
            try connection.execute("CREATE TABLE SHOULD_NOT_EXIST (id INTEGER);")
            XCTFail("Expected write through read-only connection to fail")
        } catch let error as AppleNotesStoreError {
            XCTAssertTrue(error.errorDescription?.contains("schema") == true)
        }
    }
}
