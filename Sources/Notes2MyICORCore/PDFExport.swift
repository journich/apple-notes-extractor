import Foundation
import WebKit

public protocol PDFRendering {
    func renderPDF(html: String, baseURL: URL?) throws -> Data
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

    public init(
        outputDirectory: URL,
        mirrorFolderTree: Bool = true,
        writeSidecarJSON: Bool = true,
        writeDebugHTML: Bool = false
    ) {
        self.outputDirectory = outputDirectory
        self.mirrorFolderTree = mirrorFolderTree
        self.writeSidecarJSON = writeSidecarJSON
        self.writeDebugHTML = writeDebugHTML
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
        case warnings
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
        try pdfData.write(to: pdfURL, options: .atomic)

        let contentHash = "sha256:\(hasher.contentHash(for: document))"
        let sidecarURL: URL?
        if options.writeSidecarJSON {
            sidecarURL = directory.appendingPathComponent(base).appendingPathExtension("json")
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
                warnings: document.warnings
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
        let html = htmlRenderer.render(document)
        let baseURL = document.htmlPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
        let pdfData = try pdfRenderer.renderPDF(html: html, baseURL: baseURL)
        return try writer.write(document: document, pdfData: pdfData, options: options)
    }
}

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
