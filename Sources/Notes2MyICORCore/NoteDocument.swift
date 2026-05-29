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
        self.warnings = warnings
    }
}

public struct NoteDocumentAsset: Codable, Equatable, Sendable {
    public var reference: String
    public var resolvedPath: String?
    public var hashKey: String

    public init(reference: String, resolvedPath: String?, hashKey: String) {
        self.reference = reference
        self.resolvedPath = resolvedPath
        self.hashKey = hashKey
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
            warnings: warnings(parsedNote: parsedNote, metadata: metadata)
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
    public init() {}

    public func resolveAssets(html: String, htmlPath: String?) -> [NoteDocumentAsset] {
        let references = extractAssetReferences(from: html)
        let baseURL = htmlPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }

        return references.map { reference in
            let resolvedPath: String?
            if isLocalRelativeReference(reference), let baseURL {
                resolvedPath = baseURL.appendingPathComponent(reference).standardizedFileURL.path
            } else if reference.hasPrefix("/") {
                resolvedPath = URL(fileURLWithPath: reference).standardizedFileURL.path
            } else {
                resolvedPath = nil
            }

            return NoteDocumentAsset(
                reference: reference,
                resolvedPath: resolvedPath,
                hashKey: hashKey(for: reference)
            )
        }.sorted { $0.hashKey < $1.hashKey }
    }

    private func extractAssetReferences(from html: String) -> [String] {
        let pattern = #"(?:src|href)\s*=\s*["']([^"']+)["']"#
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
