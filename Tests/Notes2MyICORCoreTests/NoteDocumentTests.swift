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

    func testAssetPathsDecodePercentEscapesForFilesystemLookup() throws {
        let resolver = NoteDocumentAssetResolver()
        let assets = resolver.resolveAssets(
            html: #"<img src="assets/Apple%20Pencil%20Drawing.png">"#,
            htmlPath: "/tmp/parser/notes_rip/html/note-uuid.html"
        )

        XCTAssertEqual(assets.first?.reference, "assets/Apple%20Pencil%20Drawing.png")
        XCTAssertEqual(assets.first?.resolvedPath, "/tmp/parser/notes_rip/html/assets/Apple Pencil Drawing.png")
        XCTAssertEqual(assets.first?.kind, .sketchOrHandwriting)
    }

    func testSketchOrHandwritingAssetMapsToEmbeddedObjectModel() throws {
        let directory = try TemporaryDirectory()
        let htmlURL = directory.url.appendingPathComponent("note.html")
        let assetURL = directory.url.appendingPathComponent("Apple Pencil Drawing.png")
        try Data("image fixture".utf8).write(to: assetURL)
        try Data(#"<img src="Apple Pencil Drawing.png">"#.utf8).write(to: htmlURL)

        let html = try String(contentsOf: htmlURL)
        let assets = NoteDocumentAssetResolver().resolveAssets(html: html, htmlPath: htmlURL.path)
        let embeddedObjects = NoteDocumentEmbeddedObjectDetector().detect(html: html, assets: assets)

        XCTAssertEqual(assets.first?.kind, .sketchOrHandwriting)
        XCTAssertEqual(assets.first?.exists, true)
        XCTAssertEqual(embeddedObjects.first?.kind, .sketchOrHandwriting)
        XCTAssertEqual(embeddedObjects.first?.status, .renderedInline)
    }

    func testHTMLReferenceIsNotClassifiedAsHandwritingFromDirectoryName() throws {
        let classifier = NoteDocumentEmbeddedObjectClassifier()

        let kind = classifier.kind(
            reference: "../index.html",
            resolvedPath: "/tmp/notes2myicor-handwriting-check/notes_rip/html/index.html"
        )

        XCTAssertEqual(kind, .html)
    }

    func testMissingImageProducesWarning() throws {
        let directory = try TemporaryDirectory()
        let htmlURL = directory.url.appendingPathComponent("note.html")
        let html = #"<img src="missing-image.png">"#
        try Data(html.utf8).write(to: htmlURL)

        let assets = NoteDocumentAssetResolver().resolveAssets(html: html, htmlPath: htmlURL.path)
        let embeddedObjects = NoteDocumentEmbeddedObjectDetector().detect(html: html, assets: assets)
        let warnings = NoteDocumentEmbeddedObjectDetector().warnings(for: embeddedObjects)

        XCTAssertEqual(assets.first?.kind, .image)
        XCTAssertEqual(assets.first?.exists, false)
        XCTAssertEqual(embeddedObjects.first?.status, .missing)
        XCTAssertEqual(warnings, ["Embedded object is referenced but missing from parser output: missing-image.png"])
    }

    func testTableElementsMapToEmbeddedObjectModel() throws {
        let html = "<table><tr><td>Cell</td></tr></table>"

        let embeddedObjects = NoteDocumentEmbeddedObjectDetector().detect(html: html, assets: [])

        XCTAssertEqual(embeddedObjects.count, 1)
        XCTAssertEqual(embeddedObjects[0].kind, .table)
        XCTAssertEqual(embeddedObjects[0].status, .renderedInline)
        XCTAssertEqual(embeddedObjects[0].detail, "HTML table elements detected: 1")
    }

    func testUnsupportedEmbeddedObjectProducesWarning() throws {
        let directory = try TemporaryDirectory()
        let htmlURL = directory.url.appendingPathComponent("note.html")
        let assetURL = directory.url.appendingPathComponent("object.custom")
        try Data("fixture".utf8).write(to: assetURL)
        let html = #"<a href="object.custom">Object</a>"#
        try Data(html.utf8).write(to: htmlURL)

        let assets = NoteDocumentAssetResolver().resolveAssets(html: html, htmlPath: htmlURL.path)
        let embeddedObjects = NoteDocumentEmbeddedObjectDetector().detect(html: html, assets: assets)
        let warnings = NoteDocumentEmbeddedObjectDetector().warnings(for: embeddedObjects)

        XCTAssertEqual(embeddedObjects.first?.kind, .unknown)
        XCTAssertEqual(embeddedObjects.first?.status, .unsupported)
        XCTAssertEqual(warnings, ["Embedded object has an unsupported or unknown type: object.custom"])
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

    func testHTMLRendererInlinesResolvedImageAssetsForPDFRendering() throws {
        let directory = try TemporaryDirectory()
        let imageURL = directory.url.appendingPathComponent("Preview.png")
        try Data("image bytes".utf8).write(to: imageURL)
        let document = fixtureDocument(
            htmlContent: #"<p><img src="../../../files/Preview.png"></p>"#,
            assets: [
                NoteDocumentAsset(
                    reference: "../../../files/Preview.png",
                    resolvedPath: imageURL.path,
                    hashKey: "../../../files/Preview.png",
                    kind: .sketchOrHandwriting,
                    exists: true
                ),
            ]
        )

        let html = NoteDocumentHTMLRenderer().render(document)

        XCTAssertTrue(html.contains(#"src="data:image/png;base64,"#))
        XCTAssertFalse(html.contains(#"src="../../../files/Preview.png""#))
    }

    func testBuilderAddsMetadataAndParserWarnings() throws {
        let directory = try TemporaryDirectory()
        let htmlURL = directory.url.appendingPathComponent("note-uuid.html")
        try Data("asset fixture".utf8).write(to: directory.url.appendingPathComponent("asset.png"))
        let parsed = AppleCloudNotesParsedNote(
            uuid: "note-uuid",
            title: "Parser title",
            html: #"<img src="asset.png">"#,
            jsonID: "1",
            individualHTMLPath: htmlURL.path
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
        XCTAssertEqual(document.embeddedObjects.map(\.kind), [.image])
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
