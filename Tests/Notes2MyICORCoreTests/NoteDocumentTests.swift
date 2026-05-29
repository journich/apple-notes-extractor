import Foundation
import XCTest
@testable import Notes2MyICORCore

final class NoteDocumentTests: XCTestCase {
    func testParsedNoteModelSerializesToJSON() throws {
        let document = fixtureDocument()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)
        let json = String(data: data, encoding: .utf8) ?? ""

        XCTAssertTrue(json.contains(#""uuid":"note-uuid""#))
        XCTAssertTrue(json.contains(#""title":"Fixture""#))
        XCTAssertTrue(json.contains(#""accountName":"iCloud""#))
        XCTAssertTrue(json.contains(#""folderPath":"Capture""#))
    }

    func testMetadataHeaderEscapesTitlesAndFolders() throws {
        let document = NoteDocument(
            uuid: "note-uuid",
            title: #"A&B "Note""#,
            accountName: "iCloud <Main>",
            folderPath: "Capture > PDFs",
            createdAt: nil,
            modifiedAt: nil,
            htmlPath: nil,
            htmlContent: "<p>Body</p>",
            assets: []
        )

        let header = NoteDocumentHTMLRenderer().metadataHeader(for: document)

        XCTAssertTrue(header.contains("A&amp;B &quot;Note&quot;"))
        XCTAssertTrue(header.contains("iCloud &lt;Main&gt;"))
        XCTAssertTrue(header.contains("Capture &gt; PDFs"))
        XCTAssertFalse(header.contains("iCloud <Main>"))
    }

    func testAssetPathsResolveRelativeToIndividualHTMLFile() throws {
        let resolver = NoteDocumentAssetResolver()
        let assets = resolver.resolveAssets(
            html: #"<img src="assets/image 1.png"><a href="https://example.invalid/nope">skip</a>"#,
            htmlPath: "/tmp/parser/notes_rip/html/note-uuid.html"
        )

        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(assets[0].reference, "assets/image 1.png")
        XCTAssertEqual(assets[0].resolvedPath, "/tmp/parser/notes_rip/html/assets/image 1.png")
    }

    func testContentHashChangesWhenBodyChanges() throws {
        let first = fixtureDocument(htmlContent: "<p>One</p>")
        let second = fixtureDocument(htmlContent: "<p>Two</p>")
        let hasher = NoteDocumentHasher()

        XCTAssertNotEqual(hasher.contentHash(for: first), hasher.contentHash(for: second))
    }

    func testContentHashChangesWhenEmbeddedObjectListChanges() throws {
        let first = fixtureDocument(assets: [
            NoteDocumentAsset(reference: "a.png", resolvedPath: "/tmp/a.png", hashKey: "a.png"),
        ])
        let second = fixtureDocument(assets: [
            NoteDocumentAsset(reference: "a.png", resolvedPath: "/tmp/a.png", hashKey: "a.png"),
            NoteDocumentAsset(reference: "b.png", resolvedPath: "/tmp/b.png", hashKey: "b.png"),
        ])
        let hasher = NoteDocumentHasher()

        XCTAssertNotEqual(hasher.contentHash(for: first), hasher.contentHash(for: second))
    }

    func testContentHashIgnoresIrrelevantAbsolutePathDifferences() throws {
        let first = fixtureDocument(htmlPath: "/tmp/one/note-uuid.html", assets: [
            NoteDocumentAsset(reference: "a.png", resolvedPath: "/tmp/one/a.png", hashKey: "a.png"),
        ])
        let second = fixtureDocument(htmlPath: "/tmp/two/note-uuid.html", assets: [
            NoteDocumentAsset(reference: "a.png", resolvedPath: "/tmp/two/a.png", hashKey: "a.png"),
        ])
        let hasher = NoteDocumentHasher()

        XCTAssertEqual(hasher.contentHash(for: first), hasher.contentHash(for: second))
    }

    func testDebugHTMLWriterCreatesRenderableHTML() throws {
        let directory = try TemporaryDirectory()
        let outputDirectory = directory.url.appendingPathComponent("debug-html", isDirectory: true)
        let document = fixtureDocument()

        let written = try NoteDocumentDebugHTMLWriter().write([document], to: outputDirectory)

        XCTAssertEqual(written.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: written[0].path))
        let html = try String(contentsOf: written[0])
        XCTAssertTrue(html.contains("<!doctype html>"))
        XCTAssertTrue(html.contains(#"<base href="file:///tmp/parser/">"#))
        XCTAssertTrue(html.contains("notes2myicor-metadata"))
    }

    func testBuilderAddsMetadataAndParserWarnings() throws {
        let parsed = AppleCloudNotesParsedNote(
            uuid: "note-uuid",
            title: "Parser title",
            html: #"<img src="asset.png">"#,
            jsonID: "1",
            individualHTMLPath: "/tmp/parser/note-uuid.html"
        )
        let metadata = AppleNotesNoteMetadata(
            objectID: 1,
            uuid: "note-uuid",
            title: "Metadata title",
            snippet: nil,
            createdCoreData: nil,
            modifiedCoreData: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            modifiedAt: Date(timeIntervalSince1970: 2),
            accountObjectID: 10,
            folderObjectID: 20,
            noteDataObjectID: 30
        )

        let document = NoteDocumentBuilder().document(
            parsedNote: parsed,
            metadata: metadata,
            accountName: "iCloud",
            folderPath: "Capture"
        )

        XCTAssertEqual(document.title, "Metadata title")
        XCTAssertEqual(document.accountName, "iCloud")
        XCTAssertEqual(document.folderPath, "Capture")
        XCTAssertEqual(document.assets.map(\.hashKey), ["asset.png"])
        XCTAssertEqual(document.warnings, [])
    }

    private func fixtureDocument(
        htmlPath: String? = "/tmp/parser/note-uuid.html",
        htmlContent: String = "<p>Body</p>",
        assets: [NoteDocumentAsset] = [
            NoteDocumentAsset(reference: "a.png", resolvedPath: "/tmp/parser/a.png", hashKey: "a.png"),
        ]
    ) -> NoteDocument {
        NoteDocument(
            uuid: "note-uuid",
            title: "Fixture",
            accountName: "iCloud",
            folderPath: "Capture",
            createdAt: Date(timeIntervalSince1970: 1),
            modifiedAt: Date(timeIntervalSince1970: 2),
            htmlPath: htmlPath,
            htmlContent: htmlContent,
            assets: assets
        )
    }
}
