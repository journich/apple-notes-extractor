import Foundation
import XCTest
@testable import Notes2MyICORCore

final class PDFExportTests: XCTestCase {
    func testFilenameSanitizerRemovesUnsafeCharacters() {
        let namer = NoteOutputNamer()

        XCTAssertEqual(
            namer.sanitizeFilenameComponent("bad:/\\|?*\"<>\n\tname"),
            "bad-name"
        )
    }

    func testLongFilenamesAreTruncatedSafely() {
        let namer = NoteOutputNamer(maximumBaseLength: 24)
        let document = fixtureDocument(title: String(repeating: "A", count: 80))

        let filename = namer.baseFilename(for: document)

        XCTAssertLessThanOrEqual(filename.count, 24)
        XCTAssertFalse(filename.hasSuffix("-"))
        XCTAssertFalse(filename.hasSuffix(" "))
    }

    func testUUIDTitleFilenameStrategyIsStable() {
        let namer = NoteOutputNamer()
        let document = fixtureDocument(title: "Sketch workflow")

        XCTAssertEqual(namer.baseFilename(for: document), "note-uuid - Sketch workflow")
        XCTAssertEqual(namer.baseFilename(for: document), "note-uuid - Sketch workflow")
    }

    func testOutputPathMirrorsFolderTreeWhenConfigured() throws {
        let directory = try TemporaryDirectory()
        let writer = NoteExportWriter()
        let document = fixtureDocument(folderPath: "Capture/Sketches")

        let result = try writer.write(
            document: document,
            pdfData: Data("%PDF fixture".utf8),
            options: NoteExportOptions(outputDirectory: directory.url, mirrorFolderTree: true),
            exportedAt: Date(timeIntervalSince1970: 10)
        )

        XCTAssertTrue(result.pdfURL.path.hasSuffix("/Capture/Sketches/note-uuid - Fixture.pdf"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.pdfURL.path))
    }

    func testSidecarJSONContainsRequiredFields() throws {
        let directory = try TemporaryDirectory()
        let writer = NoteExportWriter()
        let document = fixtureDocument()

        let result = try writer.write(
            document: document,
            pdfData: Data("%PDF fixture".utf8),
            options: NoteExportOptions(outputDirectory: directory.url),
            exportedAt: Date(timeIntervalSince1970: 10)
        )

        let sidecarURL = try XCTUnwrap(result.sidecarURL)
        let data = try Data(contentsOf: sidecarURL)
        let sidecar = try JSONDecoder.withISO8601Dates.decode(NoteExportSidecar.self, from: data)

        XCTAssertEqual(sidecar.source, "Apple Notes")
        XCTAssertEqual(sidecar.noteUUID, "note-uuid")
        XCTAssertEqual(sidecar.title, "Fixture")
        XCTAssertEqual(sidecar.account, "iCloud")
        XCTAssertEqual(sidecar.folderPath, "Capture")
        XCTAssertTrue(sidecar.contentHash.hasPrefix("sha256:"))
        XCTAssertEqual(sidecar.pdfPath, result.pdfURL.path)
    }

    func testExistingPDFReplacementIsAtomicWherePractical() throws {
        let directory = try TemporaryDirectory()
        let writer = NoteExportWriter()
        let document = fixtureDocument()
        let options = NoteExportOptions(outputDirectory: directory.url)

        let first = try writer.write(document: document, pdfData: Data("old".utf8), options: options)
        let second = try writer.write(document: document, pdfData: Data("new".utf8), options: options)

        XCTAssertEqual(first.pdfURL, second.pdfURL)
        XCTAssertEqual(try String(contentsOf: second.pdfURL), "new")
    }

    func testOutputWriterReportsUnwritableDirectory() throws {
        let directory = try TemporaryDirectory()
        let fileURL = directory.url.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: fileURL)
        let writer = NoteExportWriter()

        XCTAssertThrowsError(try writer.write(
            document: fixtureDocument(),
            pdfData: Data("%PDF fixture".utf8),
            options: NoteExportOptions(outputDirectory: fileURL)
        ))
    }

    func testExporterUsesRendererAndWritesDebugHTML() throws {
        let directory = try TemporaryDirectory()
        let renderer = FakePDFRenderer()
        let exporter = NoteExporter(pdfRenderer: renderer)

        let result = try exporter.export(
            document: fixtureDocument(),
            options: NoteExportOptions(outputDirectory: directory.url, writeDebugHTML: true)
        )

        XCTAssertTrue(renderer.renderedHTML.contains("notes2myicor-metadata"))
        XCTAssertEqual(try String(contentsOf: result.pdfURL), "%PDF fake")
        XCTAssertNotNil(result.sidecarURL)
        XCTAssertNotNil(result.debugHTMLURL)
    }

    private func fixtureDocument(
        title: String = "Fixture",
        folderPath: String? = "Capture"
    ) -> NoteDocument {
        NoteDocument(
            uuid: "note-uuid",
            title: title,
            accountName: "iCloud",
            folderPath: folderPath,
            createdAt: Date(timeIntervalSince1970: 1),
            modifiedAt: Date(timeIntervalSince1970: 2),
            htmlPath: nil,
            htmlContent: "<p>Body</p>",
            assets: [],
            warnings: ["fixture warning"]
        )
    }
}

private final class FakePDFRenderer: PDFRendering {
    private(set) var renderedHTML = ""

    func renderPDF(html: String, baseURL: URL?) throws -> Data {
        renderedHTML = html
        return Data("%PDF fake".utf8)
    }
}

private extension JSONDecoder {
    static var withISO8601Dates: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
