import Foundation
import AppKit
import PDFKit
import WebKit

public protocol PDFRendering {
    func renderPDF(html: String, baseURL: URL?) throws -> Data
}

public protocol NoteExporting {
    func export(document: NoteDocument, options: NoteExportOptions) throws -> NoteExportResult
}

public enum PDFRenderError: Error, Equatable, LocalizedError {
    case navigationFailed(String)
    case timeout(String)

    public var errorDescription: String? {
        switch self {
        case .navigationFailed(let reason):
            "PDF renderer failed to load HTML: \(reason)"
        case .timeout(let step):
            "PDF renderer timed out while \(step)"
        }
    }
}

public final class WebKitPDFRenderer: PDFRendering {
    private let timeout: TimeInterval
    private let pageRect: CGRect

    public init(
        timeout: TimeInterval = 30,
        pageRect: CGRect = CGRect(x: 0, y: 0, width: 794, height: 1123)
    ) {
        self.timeout = timeout
        self.pageRect = pageRect
    }

    public func renderPDF(html: String, baseURL: URL?) throws -> Data {
        let timeout = timeout
        let pageRect = pageRect
        if Thread.isMainThread {
            return try MainActor.assumeIsolated {
                try Self.renderPDFOnMainActor(html: html, baseURL: baseURL, timeout: timeout, pageRect: pageRect)
            }
        }

        var result: Result<Data, Error>!
        DispatchQueue.main.sync {
            result = MainActor.assumeIsolated {
                Result {
                    try Self.renderPDFOnMainActor(html: html, baseURL: baseURL, timeout: timeout, pageRect: pageRect)
                }
            }
        }
        return try result.get()
    }

    @MainActor
    private static func renderPDFOnMainActor(
        html: String,
        baseURL: URL?,
        timeout: TimeInterval,
        pageRect: CGRect
    ) throws -> Data {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: pageRect, configuration: configuration)
        let session = WebKitPDFRenderSession()
        webView.navigationDelegate = session
        webView.loadHTMLString(html, baseURL: baseURL)

        try session.waitForLoad(timeout: timeout)
        try waitForImages(in: webView, timeout: timeout)

        let pdfConfiguration = WKPDFConfiguration()
        pdfConfiguration.rect = pageRect

        var pdfResult: Result<Data, Error>?
        webView.createPDF(configuration: pdfConfiguration) { result in
            pdfResult = result
        }

        let deadline = Date().addingTimeInterval(timeout)
        while pdfResult == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }

        guard let pdfResult else {
            throw PDFRenderError.timeout("creating PDF data")
        }
        return try pdfResult.get()
    }

    @MainActor
    private static func waitForImages(in webView: WKWebView, timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?

        while Date() < deadline {
            var evaluationResult: Result<Bool, Error>?
            webView.evaluateJavaScript(
                "Array.from(document.images).every(function(image) { return image.complete; })"
            ) { value, error in
                if let error {
                    evaluationResult = .failure(error)
                } else {
                    evaluationResult = .success((value as? Bool) ?? true)
                }
            }

            while evaluationResult == nil && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
            }

            switch evaluationResult {
            case .success(true):
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
                return
            case .success(false):
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            case .failure(let error):
                lastError = error
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            case nil:
                break
            }
        }

        if let lastError {
            throw PDFRenderError.navigationFailed(lastError.localizedDescription)
        }
        throw PDFRenderError.timeout("loading images")
    }
}

@MainActor
private final class WebKitPDFRenderSession: NSObject, WKNavigationDelegate {
    private var isLoaded = false
    private var loadError: Error?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadError = error
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadError = error
    }

    func waitForLoad(timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while isLoaded == false && loadError == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }

        if let loadError {
            throw PDFRenderError.navigationFailed(loadError.localizedDescription)
        }
        guard isLoaded else {
            throw PDFRenderError.timeout("loading HTML")
        }
    }
}

public struct NoteExportOptions: Equatable, Sendable {
    public var outputDirectory: URL
    public var mirrorFolderTree: Bool
    public var writeSidecarJSON: Bool
    public var writeDebugHTML: Bool
    public var embeddedPDFMode: EmbeddedPDFMode

    public init(
        outputDirectory: URL,
        mirrorFolderTree: Bool = true,
        writeSidecarJSON: Bool = true,
        writeDebugHTML: Bool = false,
        embeddedPDFMode: EmbeddedPDFMode = .append
    ) {
        self.outputDirectory = outputDirectory
        self.mirrorFolderTree = mirrorFolderTree
        self.writeSidecarJSON = writeSidecarJSON
        self.writeDebugHTML = writeDebugHTML
        self.embeddedPDFMode = embeddedPDFMode
    }
}

public enum EmbeddedPDFMode: String, Codable, Equatable, Sendable {
    case append
    case separate
    case linkOnly = "link-only"

    public init(configValue: String, appendEmbeddedPDFs: Bool = true) {
        if appendEmbeddedPDFs == false {
            self = .linkOnly
            return
        }
        self = EmbeddedPDFMode(rawValue: configValue) ?? .append
    }
}

public struct NoteExportResult: Equatable, Sendable {
    public var pdfURL: URL
    public var sidecarURL: URL?
    public var debugHTMLURL: URL?
    public var contentHash: String

    public init(pdfURL: URL, sidecarURL: URL?, debugHTMLURL: URL?, contentHash: String) {
        self.pdfURL = pdfURL
        self.sidecarURL = sidecarURL
        self.debugHTMLURL = debugHTMLURL
        self.contentHash = contentHash
    }
}

public struct NoteExportSidecar: Codable, Equatable, Sendable {
    public var source: String
    public var noteUUID: String
    public var title: String
    public var account: String?
    public var folderPath: String?
    public var createdAt: Date?
    public var modifiedAt: Date?
    public var exportedAt: Date
    public var contentHash: String
    public var pdfPath: String
    public var embeddedPDFMode: EmbeddedPDFMode
    public var embeddedObjects: [NoteExportEmbeddedObject]
    public var warnings: [String]

    public init(
        source: String = "Apple Notes",
        noteUUID: String,
        title: String,
        account: String?,
        folderPath: String?,
        createdAt: Date?,
        modifiedAt: Date?,
        exportedAt: Date,
        contentHash: String,
        pdfPath: String,
        embeddedPDFMode: EmbeddedPDFMode = .append,
        embeddedObjects: [NoteExportEmbeddedObject] = [],
        warnings: [String]
    ) {
        self.source = source
        self.noteUUID = noteUUID
        self.title = title
        self.account = account
        self.folderPath = folderPath
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.exportedAt = exportedAt
        self.contentHash = contentHash
        self.pdfPath = pdfPath
        self.embeddedPDFMode = embeddedPDFMode
        self.embeddedObjects = embeddedObjects
        self.warnings = warnings
    }

    enum CodingKeys: String, CodingKey {
        case source
        case noteUUID = "note_uuid"
        case title
        case account
        case folderPath = "folder_path"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
        case exportedAt = "exported_at"
        case contentHash = "content_hash"
        case pdfPath = "pdf_path"
        case embeddedPDFMode = "embedded_pdf_mode"
        case embeddedObjects = "embedded_objects"
        case warnings
    }
}

public struct NoteExportEmbeddedObject: Codable, Equatable, Sendable {
    public var kind: NoteDocumentEmbeddedObjectKind
    public var reference: String?
    public var resolvedPath: String?
    public var exportedPath: String?
    public var status: NoteDocumentEmbeddedObjectStatus
    public var detail: String?

    public init(
        kind: NoteDocumentEmbeddedObjectKind,
        reference: String?,
        resolvedPath: String?,
        exportedPath: String? = nil,
        status: NoteDocumentEmbeddedObjectStatus,
        detail: String? = nil
    ) {
        self.kind = kind
        self.reference = reference
        self.resolvedPath = resolvedPath
        self.exportedPath = exportedPath
        self.status = status
        self.detail = detail
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case reference
        case resolvedPath = "resolved_path"
        case exportedPath = "exported_path"
        case status
        case detail
    }
}

public struct NoteOutputNamer {
    public let maximumBaseLength: Int

    public init(maximumBaseLength: Int = 120) {
        self.maximumBaseLength = maximumBaseLength
    }

    public func baseFilename(for document: NoteDocument) -> String {
        let uuid = sanitizeFilenameComponent(document.uuid)
        let title = sanitizeFilenameComponent(document.title)
        let raw = title.isEmpty ? uuid : "\(uuid) - \(title)"
        return truncate(raw, maximumLength: maximumBaseLength)
    }

    public func folderComponents(for folderPath: String?) -> [String] {
        guard let folderPath else {
            return []
        }
        return folderPath
            .split(separator: "/")
            .map { sanitizeFilenameComponent(String($0)) }
            .filter { $0.isEmpty == false }
    }

    public func sanitizeFilenameComponent(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\|?*\"<>")
            .union(.newlines)
            .union(CharacterSet(charactersIn: "\t"))
            .union(.controlCharacters)
        let scalars = value.unicodeScalars.map { scalar in
            invalid.contains(scalar) ? "-" : Character(scalar)
        }
        let sanitized = String(scalars)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        return sanitized
    }

    private func truncate(_ value: String, maximumLength: Int) -> String {
        guard value.count > maximumLength else {
            return value
        }
        return String(value.prefix(maximumLength)).trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
    }
}

public struct NoteExportWriter {
    public let fileManager: FileManager
    public let namer: NoteOutputNamer
    public let htmlRenderer: NoteDocumentHTMLRenderer
    public let hasher: NoteDocumentHasher

    public init(
        fileManager: FileManager = .default,
        namer: NoteOutputNamer = NoteOutputNamer(),
        htmlRenderer: NoteDocumentHTMLRenderer = NoteDocumentHTMLRenderer(),
        hasher: NoteDocumentHasher = NoteDocumentHasher()
    ) {
        self.fileManager = fileManager
        self.namer = namer
        self.htmlRenderer = htmlRenderer
        self.hasher = hasher
    }

    public func write(
        document: NoteDocument,
        pdfData: Data,
        options: NoteExportOptions,
        exportedAt: Date = Date()
    ) throws -> NoteExportResult {
        let directory = outputDirectory(for: document, options: options)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let base = namer.baseFilename(for: document)
        let pdfURL = directory.appendingPathComponent(base).appendingPathExtension("pdf")
        let embeddedPDFResult = try EmbeddedPDFExportProcessor(fileManager: fileManager).process(
            pdfData: pdfData,
            document: document,
            outputDirectory: directory,
            baseFilename: base,
            mode: options.embeddedPDFMode
        )
        try embeddedPDFResult.pdfData.write(to: pdfURL, options: .atomic)

        let contentHash = "sha256:\(hasher.contentHash(for: document))"
        let sidecarURL: URL?
        if options.writeSidecarJSON {
            sidecarURL = directory.appendingPathComponent(base).appendingPathExtension("json")
            let warnings = uniqueWarnings(document.warnings + embeddedPDFResult.warnings)
            let sidecar = NoteExportSidecar(
                noteUUID: document.uuid,
                title: document.title,
                account: document.accountName,
                folderPath: document.folderPath,
                createdAt: document.createdAt,
                modifiedAt: document.modifiedAt,
                exportedAt: exportedAt,
                contentHash: contentHash,
                pdfPath: pdfURL.path,
                embeddedPDFMode: options.embeddedPDFMode,
                embeddedObjects: embeddedPDFResult.embeddedObjects,
                warnings: warnings
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(sidecar).write(to: sidecarURL!, options: .atomic)
        } else {
            sidecarURL = nil
        }

        let debugHTMLURL: URL?
        if options.writeDebugHTML {
            debugHTMLURL = directory.appendingPathComponent(base).appendingPathExtension("html")
            try Data(htmlRenderer.render(document).utf8).write(to: debugHTMLURL!, options: .atomic)
        } else {
            debugHTMLURL = nil
        }

        return NoteExportResult(
            pdfURL: pdfURL,
            sidecarURL: sidecarURL,
            debugHTMLURL: debugHTMLURL,
            contentHash: contentHash
        )
    }

    private func outputDirectory(for document: NoteDocument, options: NoteExportOptions) -> URL {
        guard options.mirrorFolderTree else {
            return options.outputDirectory
        }

        return namer.folderComponents(for: document.folderPath).reduce(options.outputDirectory) { url, component in
            url.appendingPathComponent(component, isDirectory: true)
        }
    }

    private func uniqueWarnings(_ warnings: [String]) -> [String] {
        var seen: Set<String> = []
        return warnings.filter { warning in
            if seen.contains(warning) {
                return false
            }
            seen.insert(warning)
            return true
        }
    }
}

public struct EmbeddedPDFExportResult: Equatable, Sendable {
    public var pdfData: Data
    public var embeddedObjects: [NoteExportEmbeddedObject]
    public var warnings: [String]
}

public struct EmbeddedPDFExportProcessor {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func process(
        pdfData: Data,
        document: NoteDocument,
        outputDirectory: URL,
        baseFilename: String,
        mode: EmbeddedPDFMode
    ) throws -> EmbeddedPDFExportResult {
        var warnings: [String] = []
        var exportedPaths: [String: String] = [:]
        var outputPDFData = pdfData

        let embeddedPDFs = document.embeddedObjects.filter {
            $0.kind == .pdf && $0.status != .missing && $0.resolvedPath != nil
        }

        switch mode {
        case .append:
            let appendResult = appendEmbeddedPDFs(embeddedPDFs, to: pdfData)
            outputPDFData = appendResult.pdfData
            warnings.append(contentsOf: appendResult.warnings)
        case .separate:
            exportedPaths = try copyEmbeddedPDFs(
                embeddedPDFs,
                to: outputDirectory,
                baseFilename: baseFilename
            )
        case .linkOnly:
            break
        }

        let imageAppendResult = appendImageAssets(imageAssetsToAppend(for: document), to: outputPDFData)
        outputPDFData = imageAppendResult.pdfData
        warnings.append(contentsOf: imageAppendResult.warnings)

        let exportObjects = document.embeddedObjects.map { object in
            let exportedPath = object.resolvedPath.flatMap { exportedPaths[$0] }
            return NoteExportEmbeddedObject(
                kind: object.kind,
                reference: object.reference,
                resolvedPath: object.resolvedPath,
                exportedPath: exportedPath,
                status: object.status,
                detail: exportDetail(for: object, mode: mode, exportedPath: exportedPath)
            )
        }

        return EmbeddedPDFExportResult(
            pdfData: outputPDFData,
            embeddedObjects: exportObjects,
            warnings: warnings
        )
    }

    private func appendEmbeddedPDFs(
        _ embeddedPDFs: [NoteDocumentEmbeddedObject],
        to pdfData: Data
    ) -> EmbeddedPDFExportResult {
        guard embeddedPDFs.isEmpty == false else {
            return EmbeddedPDFExportResult(pdfData: pdfData, embeddedObjects: [], warnings: [])
        }
        guard let outputDocument = PDFDocument(data: pdfData) else {
            return EmbeddedPDFExportResult(
                pdfData: pdfData,
                embeddedObjects: [],
                warnings: ["Embedded PDF append mode was requested, but the rendered note PDF could not be opened for appending."]
            )
        }

        var warnings: [String] = []
        for embeddedPDF in embeddedPDFs {
            guard let path = embeddedPDF.resolvedPath else {
                continue
            }
            let attachmentURL = URL(fileURLWithPath: path)
            guard let attachmentDocument = PDFDocument(url: attachmentURL), attachmentDocument.pageCount > 0 else {
                warnings.append("Embedded PDF could not be appended and remains linked in sidecar JSON: \(embeddedPDF.reference ?? path)")
                continue
            }
            for pageIndex in 0..<attachmentDocument.pageCount {
                guard let page = attachmentDocument.page(at: pageIndex) else {
                    continue
                }
                outputDocument.insert(page, at: outputDocument.pageCount)
            }
        }

        guard let outputData = outputDocument.dataRepresentation() else {
            return EmbeddedPDFExportResult(
                pdfData: pdfData,
                embeddedObjects: [],
                warnings: warnings + ["Embedded PDF append mode was requested, but the combined PDF could not be serialized."]
            )
        }

        return EmbeddedPDFExportResult(pdfData: outputData, embeddedObjects: [], warnings: warnings)
    }

    private func appendImageAssets(
        _ assets: [NoteDocumentAsset],
        to pdfData: Data
    ) -> EmbeddedPDFExportResult {
        let imageAssets = assets.filter {
            [.image, .sketchOrHandwriting, .scannedDocument].contains($0.kind) && $0.resolvedPath != nil
        }
        guard imageAssets.isEmpty == false else {
            return EmbeddedPDFExportResult(pdfData: pdfData, embeddedObjects: [], warnings: [])
        }
        guard let outputDocument = PDFDocument(data: pdfData) else {
            return EmbeddedPDFExportResult(
                pdfData: pdfData,
                embeddedObjects: [],
                warnings: ["Image attachment append was requested, but the rendered note PDF could not be opened."]
            )
        }

        var warnings: [String] = []
        for asset in imageAssets {
            guard let path = asset.resolvedPath,
                  let image = NSImage(contentsOfFile: path),
                  let page = PDFPage(image: image) else {
                warnings.append("Image attachment could not be appended and remains linked in sidecar JSON: \(asset.reference)")
                continue
            }
            outputDocument.insert(page, at: outputDocument.pageCount)
        }

        guard let outputData = outputDocument.dataRepresentation() else {
            return EmbeddedPDFExportResult(
                pdfData: pdfData,
                embeddedObjects: [],
                warnings: warnings + ["Image attachments were appended, but the combined PDF could not be serialized."]
            )
        }

        return EmbeddedPDFExportResult(pdfData: outputData, embeddedObjects: [], warnings: warnings)
    }

    private func imageAssetsToAppend(for document: NoteDocument) -> [NoteDocumentAsset] {
        let inlineImageReferences = imageSourceReferences(in: document.htmlContent)
        return document.assets.filter { asset in
            [.image, .sketchOrHandwriting, .scannedDocument].contains(asset.kind)
                && asset.resolvedPath != nil
                && inlineImageReferences.contains(asset.reference) == false
        }
    }

    private func imageSourceReferences(in html: String) -> Set<String> {
        let pattern = #"<img\b[^>]*\bsrc\s*=\s*(["'])([^"']+)\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        var references = Set<String>()
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html))
        for match in matches {
            guard let range = Range(match.range(at: 2), in: html) else {
                continue
            }
            references.insert(String(html[range]))
        }
        return references
    }

    private func copyEmbeddedPDFs(
        _ embeddedPDFs: [NoteDocumentEmbeddedObject],
        to outputDirectory: URL,
        baseFilename: String
    ) throws -> [String: String] {
        var exportedPaths: [String: String] = [:]
        for (index, embeddedPDF) in embeddedPDFs.enumerated() {
            guard let sourcePath = embeddedPDF.resolvedPath else {
                continue
            }
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let attachmentURL = outputDirectory
                .appendingPathComponent("\(baseFilename) - embedded-\(index + 1)")
                .appendingPathExtension("pdf")
            if fileManager.fileExists(atPath: attachmentURL.path) {
                try fileManager.removeItem(at: attachmentURL)
            }
            try fileManager.copyItem(at: sourceURL, to: attachmentURL)
            exportedPaths[sourcePath] = attachmentURL.path
        }
        return exportedPaths
    }

    private func exportDetail(
        for object: NoteDocumentEmbeddedObject,
        mode: EmbeddedPDFMode,
        exportedPath: String?
    ) -> String? {
        guard object.kind == .pdf else {
            return object.detail
        }
        switch mode {
        case .append:
            return "Embedded PDF pages are appended to the rendered note PDF when the asset can be opened."
        case .separate:
            if exportedPath != nil {
                return "Embedded PDF was copied as a separate file."
            }
            return "Embedded PDF remains linked because no separate export path was produced."
        case .linkOnly:
            return "Embedded PDF remains linked and is recorded in sidecar JSON."
        }
    }
}

public struct NoteExporter {
    public let pdfRenderer: PDFRendering
    public let htmlRenderer: NoteDocumentHTMLRenderer
    public let writer: NoteExportWriter

    public init(
        pdfRenderer: PDFRendering = WebKitPDFRenderer(),
        htmlRenderer: NoteDocumentHTMLRenderer = NoteDocumentHTMLRenderer(),
        writer: NoteExportWriter = NoteExportWriter()
    ) {
        self.pdfRenderer = pdfRenderer
        self.htmlRenderer = htmlRenderer
        self.writer = writer
    }

    public func export(document: NoteDocument, options: NoteExportOptions) throws -> NoteExportResult {
        let html = htmlRenderer.render(document, includeMetadataHeader: false)
        let baseURL = document.htmlPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
        let pdfData = try pdfRenderer.renderPDF(html: html, baseURL: baseURL)
        return try writer.write(document: document, pdfData: pdfData, options: options)
    }
}

extension NoteExporter: NoteExporting {}

public struct NoteExportFormatter {
    public init() {}

    public func format(_ result: NoteExportResult) -> String {
        var lines = [
            "Export complete:",
            "PDF: \(result.pdfURL.path)",
            "Content hash: \(result.contentHash)",
        ]
        if let sidecarURL = result.sidecarURL {
            lines.append("Sidecar JSON: \(sidecarURL.path)")
        }
        if let debugHTMLURL = result.debugHTMLURL {
            lines.append("Debug HTML: \(debugHTMLURL.path)")
        }
        return lines.joined(separator: "\n")
    }
}
