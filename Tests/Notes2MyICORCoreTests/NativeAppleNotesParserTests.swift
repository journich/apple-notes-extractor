import Foundation
import XCTest
@testable import Notes2MyICORCore

final class NativeAppleNotesParserTests: XCTestCase {
    func testGzipDecompressionWorksForFixturePayload() throws {
        let data = try Data(hex: Self.gzipHelloHex)

        let decompressed = try GzipDecompressor().decompress(data)

        XCTAssertEqual(String(data: decompressed, encoding: .utf8), "hello")
    }

    func testInvalidGzipDataProducesClearError() {
        XCTAssertThrowsError(try GzipDecompressor().decompress(Data("not gzip".utf8))) { error in
            XCTAssertTrue(error.localizedDescription.contains("expected gzipped"))
        }
    }

    func testSimpleProtobufFixtureDecodesTextAndWarnings() throws {
        let protobuf = try Data(hex: Self.simpleNoteProtobufHex)

        let result = try NativeNoteStoreProtobufDecoder().decode(protobuf)

        XCTAssertEqual(result.noteText, "Title")
        XCTAssertTrue(result.warnings.contains("Native parser does not yet apply Apple Notes attribute runs."))
    }

    func testSimpleTextNoteModelRendersExpectedHTML() throws {
        let html = NativeNoteHTMLRenderer().renderPlainText("Title\n<Body>")

        XCTAssertTrue(html.contains("<p>Title</p>"))
        XCTAssertTrue(html.contains("<p>&lt;Body&gt;</p>"))
    }

    func testNativeParserLoadsZDataFromFixtureDatabase() throws {
        let directory = try TemporaryDirectory()
        let databaseURL = directory.url.appendingPathComponent("NoteStore.sqlite")
        try createNativeParserFixtureDatabase(at: databaseURL)

        let parser = NativeAppleNotesParser(config: NativeAppleNotesParserConfig(
            databaseURL: databaseURL,
            outputDirectory: directory.url.appendingPathComponent("native-output", isDirectory: true)
        ))

        let result = try parser.parse(notesContainer: directory.url, noteUUIDs: ["native-note-uuid"])

        XCTAssertEqual(result.notes.count, 1)
        XCTAssertEqual(result.notes[0].uuid, "native-note-uuid")
        XCTAssertEqual(result.notes[0].title, "Native fixture")
        XCTAssertTrue(result.notes[0].html.contains("<p>Title</p>"))
        XCTAssertTrue(result.standardError.contains("attribute runs"))
    }

    func testParserModeSelectionUsesNativeSwiftWithoutParserScript() throws {
        let directory = try TemporaryDirectory()
        let databaseURL = directory.url.appendingPathComponent("NoteStore.sqlite")
        try createNativeParserFixtureDatabase(at: databaseURL)
        let recorder = OutputRecorder()

        let code = AppRunner(output: recorder.output, errorOutput: recorder.error)
            .run(arguments: [
                "parse",
                "--parser-mode", "native-swift",
                "--database", databaseURL.path,
                "--note-uuid", "native-note-uuid",
            ])

        XCTAssertEqual(code, 0)
        XCTAssertTrue(recorder.stdout.contains("Parsed notes: 1"))
        XCTAssertTrue(recorder.stdout.contains("Note documents: 1"))
    }

    private func createNativeParserFixtureDatabase(at url: URL) throws {
        try SQLiteFixture.createDatabase(
            at: url,
            sql: """
            CREATE TABLE ZICCLOUDSYNCINGOBJECT (
                Z_PK INTEGER PRIMARY KEY,
                ZIDENTIFIER TEXT,
                ZTITLE1 TEXT,
                ZTITLE TEXT,
                ZNOTEDATA INTEGER
            );

            CREATE TABLE ZICNOTEDATA (
                Z_PK INTEGER PRIMARY KEY,
                ZDATA BLOB
            );

            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER, ZTITLE1, ZNOTEDATA)
            VALUES (1, 'native-note-uuid', 'Native fixture', 10);

            INSERT INTO ZICNOTEDATA (Z_PK, ZDATA)
            VALUES (10, X'\(Self.simpleNoteProtobufGzipHex)');
            """
        )
    }

    private static let gzipHelloHex = "1f8b080034301a6a0003cb48cdc9c9070086a6103605000000"
    private static let simpleNoteProtobufHex = "120f10011a0b12055469746c652a020805"
    private static let simpleNoteProtobufGzipHex = "1f8b080034301a6a000313e2176094e216620dc92cc949d562e2600500c5be1d1011000000"
}

private extension Data {
    init(hex: String) throws {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            let pair = hex[index..<next]
            guard let byte = UInt8(pair, radix: 16) else {
                throw HexError.invalid
            }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}

private enum HexError: Error {
    case invalid
}
