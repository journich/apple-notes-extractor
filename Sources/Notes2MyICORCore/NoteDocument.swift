import CryptoKit
import Foundation

public struct NoteDocument: Codable, Equatable, Sendable {
    public var uuid: String
    public var title: String
    public var accountName: String?
    public var folderPath: String?
    public var createdAt: Date?
    public var modifiedAt: Date?
    public var htmlPath: String?
    public var htmlContent: String
    public var assets: [NoteDocumentAsset]
    public var embeddedObjects: [NoteDocumentEmbeddedObject]
    public var warnings: [String]

    public init(
        uuid: String,
        title: String,
        accountName: String?,
        folderPath: String?,
        createdAt: Date?,
        modifiedAt: Date?,
        htmlPath: String?,
        htmlContent: String,
        assets: [NoteDocumentAsset],
        embeddedObjects: [NoteDocumentEmbeddedObject] = [],
        warnings: [String] = []
    ) {
        self.uuid = uuid
        self.title = title
        self.accountName = accountName
        self.folderPath = folderPath
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.htmlPath = htmlPath
        self.htmlContent = htmlContent
        self.assets = assets
        self.embeddedObjects = embeddedObjects
        self.warnings = warnings
    }
}

public enum NoteDocumentEmbeddedObjectKind: String, Codable, Equatable, Sendable {
    case image
    case sketchOrHandwriting = "sketch_or_handwriting"
    case scannedDocument = "scanned_document"
    case pdf
    case table
    case audio
    case video
    case text
    case html
    case archive
    case unknown
}

public enum NoteDocumentEmbeddedObjectStatus: String, Codable, Equatable, Sendable {
    case renderedInline = "rendered_inline"
    case linked
    case missing
    case unsupported
    case detected
}

public struct NoteDocumentAsset: Codable, Equatable, Sendable {
    public var reference: String
    public var resolvedPath: String?
    public var hashKey: String
    public var kind: NoteDocumentEmbeddedObjectKind
    public var exists: Bool?

    public init(
        reference: String,
        resolvedPath: String?,
        hashKey: String,
        kind: NoteDocumentEmbeddedObjectKind = .unknown,
        exists: Bool? = nil
    ) {
        self.reference = reference
        self.resolvedPath = resolvedPath
        self.hashKey = hashKey
        self.kind = kind
        self.exists = exists
    }
}

public struct NoteDocumentEmbeddedObject: Codable, Equatable, Sendable {
    public var kind: NoteDocumentEmbeddedObjectKind
    public var reference: String?
    public var resolvedPath: String?
    public var status: NoteDocumentEmbeddedObjectStatus
    public var detail: String?

    public init(
        kind: NoteDocumentEmbeddedObjectKind,
        reference: String?,
        resolvedPath: String?,
        status: NoteDocumentEmbeddedObjectStatus,
        detail: String? = nil
    ) {
        self.kind = kind
        self.reference = reference
        self.resolvedPath = resolvedPath
        self.status = status
        self.detail = detail
    }
}

public struct NoteDocumentBuilder {
    public init() {}

    public func document(
        parsedNote: AppleCloudNotesParsedNote,
        metadata: AppleNotesNoteMetadata? = nil,
        accountName: String? = nil,
        folderPath: String? = nil
    ) -> NoteDocument {
        let title = metadata?.title.isEmpty == false ? metadata?.title ?? parsedNote.title : parsedNote.title
        let htmlPath = parsedNote.individualHTMLPath
        let assets = NoteDocumentAssetResolver().resolveAssets(
            html: parsedNote.html,
            htmlPath: htmlPath
        )
        let embeddedObjects = NoteDocumentEmbeddedObjectDetector().detect(html: parsedNote.html, assets: assets)
        let warnings = warnings(parsedNote: parsedNote, metadata: metadata)
            + NoteDocumentEmbeddedObjectDetector().warnings(for: embeddedObjects)

        return NoteDocument(
            uuid: parsedNote.uuid,
            title: title,
            accountName: accountName,
            folderPath: folderPath,
            createdAt: metadata?.createdAt,
            modifiedAt: metadata?.modifiedAt,
            htmlPath: htmlPath,
            htmlContent: parsedNote.html,
            assets: assets,
            embeddedObjects: embeddedObjects,
            warnings: warnings
        )
    }

    private func warnings(parsedNote: AppleCloudNotesParsedNote, metadata: AppleNotesNoteMetadata?) -> [String] {
        var result: [String] = []
        if parsedNote.individualHTMLPath == nil {
            result.append("Parser did not provide an individual HTML file path.")
        }
        if metadata == nil {
            result.append("Apple Notes metadata was not attached to this parsed note.")
        }
        return result
    }
}

public struct NoteDocumentAssetResolver {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func resolveAssets(html: String, htmlPath: String?) -> [NoteDocumentAsset] {
        let references = extractAssetReferences(from: html)
        let baseURL = htmlPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }

        return references.map { reference in
            let fileReference = reference.removingPercentEncoding ?? reference
            let resolvedPath: String?
            if isLocalRelativeReference(reference), let baseURL {
                resolvedPath = baseURL.appendingPathComponent(fileReference).standardizedFileURL.path
            } else if reference.hasPrefix("/") {
                resolvedPath = URL(fileURLWithPath: fileReference).standardizedFileURL.path
            } else {
                resolvedPath = nil
            }

            let exists = resolvedPath.map { fileManager.fileExists(atPath: $0) }
            return NoteDocumentAsset(
                reference: reference,
                resolvedPath: resolvedPath,
                hashKey: hashKey(for: reference),
                kind: NoteDocumentEmbeddedObjectClassifier().kind(reference: reference, resolvedPath: resolvedPath),
                exists: exists
            )
        }.sorted { $0.hashKey < $1.hashKey }
    }

    private func extractAssetReferences(from html: String) -> [String] {
        let pattern = #"(?:src|href|data)\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var references: Set<String> = []
        regex.enumerateMatches(in: html, range: range) { match, _, _ in
            guard let match,
                  let referenceRange = Range(match.range(at: 1), in: html) else {
                return
            }
            let reference = String(html[referenceRange])
            if isLocalAssetReference(reference) {
                references.insert(reference)
            }
        }
        return references.sorted()
    }

    private func isLocalAssetReference(_ reference: String) -> Bool {
        let lowercased = reference.lowercased()
        return lowercased.hasPrefix("http://") == false
            && lowercased.hasPrefix("https://") == false
            && lowercased.hasPrefix("data:") == false
            && lowercased.hasPrefix("mailto:") == false
            && lowercased.hasPrefix("#") == false
    }

    private func isLocalRelativeReference(_ reference: String) -> Bool {
        reference.hasPrefix("/") == false && isLocalAssetReference(reference)
    }

    private func hashKey(for reference: String) -> String {
        reference.replacingOccurrences(of: "\\", with: "/")
    }
}

public struct NoteDocumentEmbeddedObjectClassifier {
    public init() {}

    public func kind(reference: String, resolvedPath: String?) -> NoteDocumentEmbeddedObjectKind {
        let candidate = "\(reference) \(resolvedPath ?? "")".lowercased()
        let ext = URL(fileURLWithPath: referenceWithoutQuery(reference)).pathExtension.lowercased()

        if containsSketchHint(candidate) {
            return .sketchOrHandwriting
        }
        if containsScanHint(candidate) {
            return .scannedDocument
        }
        if ["jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "webp", "svg"].contains(ext) {
            return .image
        }
        if ext == "pdf" {
            return .pdf
        }
        if ["aac", "aif", "aiff", "m4a", "mp3", "wav"].contains(ext) {
            return .audio
        }
        if ["mov", "mp4", "m4v"].contains(ext) {
            return .video
        }
        if ["txt", "rtf", "md"].contains(ext) {
            return .text
        }
        if ["html", "htm"].contains(ext) {
            return .html
        }
        if ["zip", "gz", "tgz", "tar"].contains(ext) {
            return .archive
        }
        return .unknown
    }

    private func containsSketchHint(_ value: String) -> Bool {
        ["sketch", "drawing", "handwriting", "pencil", "apple-pencil", "ink"].contains { value.contains($0) }
    }

    private func containsScanHint(_ value: String) -> Bool {
        ["scan", "scanned", "document scan"].contains { value.contains($0) }
    }

    private func referenceWithoutQuery(_ reference: String) -> String {
        reference.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? reference
    }
}

public struct NoteDocumentEmbeddedObjectDetector {
    public init() {}

    public func detect(html: String, assets: [NoteDocumentAsset]) -> [NoteDocumentEmbeddedObject] {
        var objects = assets.map(object(for:))
        objects.append(contentsOf: tableObjects(in: html))
        return objects.sorted {
            let first = "\($0.kind.rawValue):\($0.reference ?? ""):\($0.detail ?? "")"
            let second = "\($1.kind.rawValue):\($1.reference ?? ""):\($1.detail ?? "")"
            return first < second
        }
    }

    public func warnings(for objects: [NoteDocumentEmbeddedObject]) -> [String] {
        objects.compactMap { object in
            switch object.status {
            case .missing:
                let reference = object.reference ?? "unknown reference"
                return "Embedded object is referenced but missing from parser output: \(reference)"
            case .unsupported:
                let reference = object.reference ?? "unknown reference"
                return "Embedded object has an unsupported or unknown type: \(reference)"
            case .renderedInline, .linked, .detected:
                return nil
            }
        }
    }

    private func object(for asset: NoteDocumentAsset) -> NoteDocumentEmbeddedObject {
        let status: NoteDocumentEmbeddedObjectStatus
        let detail: String?

        if asset.exists == false {
            status = .missing
            detail = "Referenced file was not found on disk."
        } else {
            switch asset.kind {
            case .image, .sketchOrHandwriting, .scannedDocument:
                status = .renderedInline
                detail = renderedInlineDetail(for: asset.kind)
            case .pdf:
                status = .linked
                detail = "Embedded PDF is available as a linked asset."
            case .audio, .video, .text, .html, .archive:
                status = .linked
                detail = "Embedded file is available as a linked asset."
            case .table:
                status = .detected
                detail = nil
            case .unknown:
                status = .unsupported
                detail = "File type could not be classified from its reference."
            }
        }

        return NoteDocumentEmbeddedObject(
            kind: asset.kind,
            reference: asset.reference,
            resolvedPath: asset.resolvedPath,
            status: status,
            detail: detail
        )
    }

    private func tableObjects(in html: String) -> [NoteDocumentEmbeddedObject] {
        let pattern = #"<table\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let count = regex.numberOfMatches(in: html, range: range)
        guard count > 0 else {
            return []
        }
        return [
            NoteDocumentEmbeddedObject(
                kind: .table,
                reference: nil,
                resolvedPath: nil,
                status: .renderedInline,
                detail: "HTML table elements detected: \(count)"
            ),
        ]
    }

    private func renderedInlineDetail(for kind: NoteDocumentEmbeddedObjectKind) -> String {
        switch kind {
        case .sketchOrHandwriting:
            return "Sketch or handwriting asset is rendered inline when the parser emits an image reference."
        case .scannedDocument:
            return "Scanned document preview is rendered inline when the parser emits an image reference."
        default:
            return "Asset is rendered inline by the HTML renderer."
        }
    }
}

public struct NoteDocumentHTMLRenderer {
    private let dateFormatter: ISO8601DateFormatter

    public init(dateFormatter: ISO8601DateFormatter = ISO8601DateFormatter()) {
        self.dateFormatter = dateFormatter
    }

    public func render(_ document: NoteDocument, includeMetadataHeader: Bool = true) -> String {
        let baseTag = document.htmlPath.map { path in
            let baseURL = URL(fileURLWithPath: path).deletingLastPathComponent()
            return #"<base href="\#(escapeAttribute(baseURL.absoluteString))">"#
        } ?? ""

        let metadata = includeMetadataHeader ? metadataHeader(for: document) : ""

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(escapeText(document.title))</title>
        \(baseTag)
        </head>
        <body>
        \(metadata)
        <main class="notes2myicor-body">
        \(document.htmlContent)
        </main>
        </body>
        </html>
        """
    }

    public func metadataHeader(for document: NoteDocument) -> String {
        let rows = [
            ("Title", document.title),
            ("Account", document.accountName),
            ("Folder", document.folderPath),
            ("Created", document.createdAt.map(dateFormatter.string(from:))),
            ("Modified", document.modifiedAt.map(dateFormatter.string(from:))),
            ("UUID", document.uuid),
        ].compactMap { label, value -> String? in
            guard let value else {
                return nil
            }
            return #"<dt>\#(escapeText(label))</dt><dd>\#(escapeText(value))</dd>"#
        }.joined()

        return """
        <header class="notes2myicor-metadata">
        <dl>\(rows)</dl>
        </header>
        """
    }

    private func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func escapeAttribute(_ value: String) -> String {
        escapeText(value)
    }
}

public struct NoteDocumentHasher {
    public init() {}

    public func contentHash(for document: NoteDocument) -> String {
        var components = [
            "uuid:\(document.uuid)",
            "title:\(document.title)",
            "html:\(document.htmlContent)",
        ]
        components.append(contentsOf: document.assets.map { "asset:\($0.hashKey)" })
        let joined = components.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct NoteDocumentDebugHTMLWriter {
    public let fileManager: FileManager
    public let renderer: NoteDocumentHTMLRenderer

    public init(
        fileManager: FileManager = .default,
        renderer: NoteDocumentHTMLRenderer = NoteDocumentHTMLRenderer()
    ) {
        self.fileManager = fileManager
        self.renderer = renderer
    }

    public func write(_ documents: [NoteDocument], to directory: URL) throws -> [URL] {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return try documents.map { document in
            let filename = "\(sanitizeFilename(document.uuid)).html"
            let outputURL = directory.appendingPathComponent(filename)
            try Data(renderer.render(document).utf8).write(to: outputURL)
            return outputURL
        }
    }

    private func sanitizeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return sanitized.isEmpty ? "note" : sanitized
    }
}
