import Foundation
import zlib

public struct NativeAppleNotesParserConfig: Equatable, Sendable {
    public var databaseURL: URL
    public var outputDirectory: URL

    public init(databaseURL: URL, outputDirectory: URL) {
        self.databaseURL = databaseURL
        self.outputDirectory = outputDirectory
    }
}

public enum NativeAppleNotesParserError: Error, Equatable, LocalizedError {
    case notGzip
    case decompressionFailed(String)
    case invalidProtobuf(String)
    case noteNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .notGzip:
            "Apple Notes native parser expected gzipped ZDATA."
        case .decompressionFailed(let reason):
            "Apple Notes native parser could not decompress ZDATA: \(reason)"
        case .invalidProtobuf(let reason):
            "Apple Notes native parser could not decode note protobuf: \(reason)"
        case .noteNotFound(let uuid):
            "Apple Notes native parser output did not contain note UUID: \(uuid)"
        }
    }
}

public struct NativeAppleNotesDecodedNote: Equatable, Sendable {
    public var uuid: String
    public var title: String
    public var plainText: String
    public var warnings: [String]

    public init(uuid: String, title: String, plainText: String, warnings: [String] = []) {
        self.uuid = uuid
        self.title = title
        self.plainText = plainText
        self.warnings = warnings
    }
}

public struct NativeAppleNotesParser {
    public let config: NativeAppleNotesParserConfig
    public let fileManager: FileManager

    public init(config: NativeAppleNotesParserConfig, fileManager: FileManager = .default) {
        self.config = config
        self.fileManager = fileManager
    }

    public func parse(notesContainer: URL, noteUUIDs: [String] = []) throws -> AppleCloudNotesParserResult {
        let decoded = try decodeNotes(noteUUIDs: Set(noteUUIDs))
        for uuid in noteUUIDs where decoded.contains(where: { $0.uuid == uuid }) == false {
            throw NativeAppleNotesParserError.noteNotFound(uuid)
        }

        let parsed = decoded.map { note in
            AppleCloudNotesParsedNote(
                uuid: note.uuid,
                title: note.title,
                html: NativeNoteHTMLRenderer().renderPlainText(note.plainText, warnings: note.warnings),
                jsonID: note.uuid,
                individualHTMLPath: nil
            )
        }

        let warnings = decoded.flatMap { note in
            note.warnings.map { "\(note.uuid): \($0)" }
        }.joined(separator: "\n")

        return AppleCloudNotesParserResult(
            outputDirectory: config.outputDirectory,
            jsonPath: config.outputDirectory.appendingPathComponent("native-swift.json"),
            notes: parsed.sorted { $0.uuid < $1.uuid },
            standardOutput: "",
            standardError: warnings
        )
    }

    public func decodeNotes(noteUUIDs: Set<String> = []) throws -> [NativeAppleNotesDecodedNote] {
        let connection = try SQLiteReadOnlyConnection.open(databaseURL: config.databaseURL)
        try connection.execute("PRAGMA query_only = ON;")

        let rows = try connection.query(
            """
            SELECT
                ZICCLOUDSYNCINGOBJECT.ZIDENTIFIER,
                COALESCE(ZICCLOUDSYNCINGOBJECT.ZTITLE1, ZICCLOUDSYNCINGOBJECT.ZTITLE, '') AS DISPLAY_TITLE,
                ZICNOTEDATA.ZDATA
            FROM ZICCLOUDSYNCINGOBJECT
            JOIN ZICNOTEDATA
              ON ZICCLOUDSYNCINGOBJECT.ZNOTEDATA = ZICNOTEDATA.Z_PK
            WHERE ZICCLOUDSYNCINGOBJECT.ZIDENTIFIER IS NOT NULL
              AND ZICNOTEDATA.ZDATA IS NOT NULL
            ORDER BY ZICCLOUDSYNCINGOBJECT.ZIDENTIFIER;
            """
        )

        let decoder = NativeNoteStoreProtobufDecoder()
        var notes: [NativeAppleNotesDecodedNote] = []
        for row in rows {
            let uuid = row.string("ZIDENTIFIER")
            if noteUUIDs.isEmpty == false && noteUUIDs.contains(uuid) == false {
                continue
            }
            guard let compressedData = row.blob("ZDATA") else {
                continue
            }
            do {
                let decompressed = try GzipDecompressor().decompress(compressedData)
                let decoded = try decoder.decode(decompressed)
                notes.append(NativeAppleNotesDecodedNote(
                    uuid: uuid,
                    title: row.string("DISPLAY_TITLE"),
                    plainText: decoded.noteText,
                    warnings: decoded.warnings
                ))
            } catch {
                if noteUUIDs.contains(uuid) {
                    throw error
                }
            }
        }

        return notes
    }
}

extension NativeAppleNotesParser: NoteParsing {}

public struct GzipDecompressor {
    public init() {}

    public func decompress(_ data: Data) throws -> Data {
        guard data.count >= 2,
              data[data.startIndex] == 0x1f,
              data[data.index(after: data.startIndex)] == 0x8b else {
            throw NativeAppleNotesParserError.notGzip
        }

        var stream = z_stream()
        let initStatus = inflateInit2_(&stream, 15 + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else {
            throw NativeAppleNotesParserError.decompressionFailed("inflateInit2 returned \(initStatus)")
        }
        defer {
            inflateEnd(&stream)
        }

        var output = Data()
        let chunkSize = 16_384
        let status = data.withUnsafeBytes { rawBuffer -> Int32 in
            guard let input = rawBuffer.bindMemory(to: Bytef.self).baseAddress else {
                return Z_DATA_ERROR
            }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: input)
            stream.avail_in = uInt(data.count)

            var status: Int32 = Z_OK
            while status != Z_STREAM_END {
                var chunk = Data(count: chunkSize)
                let produced = chunk.withUnsafeMutableBytes { outputBuffer -> Int in
                    guard let baseAddress = outputBuffer.bindMemory(to: Bytef.self).baseAddress else {
                        status = Z_BUF_ERROR
                        return 0
                    }
                    stream.next_out = baseAddress
                    stream.avail_out = uInt(chunkSize)
                    status = inflate(&stream, Z_NO_FLUSH)
                    return chunkSize - Int(stream.avail_out)
                }

                if produced > 0 {
                    chunk.removeSubrange(produced..<chunk.count)
                    output.append(chunk)
                }

                if status != Z_OK && status != Z_STREAM_END {
                    return status
                }
            }
            return status
        }

        guard status == Z_STREAM_END else {
            throw NativeAppleNotesParserError.decompressionFailed("inflate returned \(status)")
        }
        return output
    }
}

public struct NativeNoteStoreProtobufDecoder {
    public init() {}

    public struct Result: Equatable, Sendable {
        public var noteText: String
        public var warnings: [String]
    }

    public func decode(_ data: Data) throws -> Result {
        let root = try ProtobufWireDecoder(data: data).decodeFields()
        var warnings: [String] = []
        warnings.append(contentsOf: unsupportedFields(in: root, allowed: [2], context: "NoteStoreProto"))
        guard let documentData = root.first(where: { $0.number == 2 })?.lengthDelimited else {
            throw NativeAppleNotesParserError.invalidProtobuf("Missing document field.")
        }

        let document = try ProtobufWireDecoder(data: documentData).decodeFields()
        warnings.append(contentsOf: unsupportedFields(in: document, allowed: [2, 3], context: "Document"))
        guard let noteData = document.first(where: { $0.number == 3 })?.lengthDelimited else {
            throw NativeAppleNotesParserError.invalidProtobuf("Missing note field.")
        }

        let note = try ProtobufWireDecoder(data: noteData).decodeFields()
        warnings.append(contentsOf: unsupportedFields(in: note, allowed: [2, 5], context: "Note"))
        if note.contains(where: { $0.number == 5 }) {
            warnings.append("Native parser does not yet apply Apple Notes attribute runs.")
        }
        guard let noteTextData = note.first(where: { $0.number == 2 })?.lengthDelimited,
              let noteText = String(data: noteTextData, encoding: .utf8) else {
            throw NativeAppleNotesParserError.invalidProtobuf("Missing UTF-8 note text.")
        }

        return Result(noteText: noteText, warnings: warnings)
    }

    private func unsupportedFields(in fields: [ProtobufField], allowed: Set<Int>, context: String) -> [String] {
        let unsupported = Set(fields.map(\.number)).subtracting(allowed)
        return unsupported.sorted().map { "\(context) field \($0) is not supported by the native parser yet." }
    }
}

public struct NativeNoteHTMLRenderer {
    public init() {}

    public func renderPlainText(_ plainText: String, warnings: [String] = []) -> String {
        let paragraphs = plainText
            .components(separatedBy: CharacterSet.newlines)
            .map { line in
                line.isEmpty ? "<p><br></p>" : "<p>\(escapeText(line))</p>"
            }
            .joined(separator: "\n")

        let warningComments = warnings.map { "<!-- \(escapeComment($0)) -->" }.joined(separator: "\n")
        return warningComments.isEmpty ? paragraphs : "\(warningComments)\n\(paragraphs)"
    }

    private func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func escapeComment(_ value: String) -> String {
        value.replacingOccurrences(of: "--", with: "- -")
    }
}

public struct ProtobufField: Equatable, Sendable {
    public var number: Int
    public var wireType: Int
    public var lengthDelimited: Data?
}

public struct ProtobufWireDecoder {
    private let data: Data

    public init(data: Data) {
        self.data = data
    }

    public func decodeFields() throws -> [ProtobufField] {
        var reader = ProtobufReader(data: data)
        var fields: [ProtobufField] = []

        while reader.isAtEnd == false {
            let key = try reader.readVarint()
            let fieldNumber = Int(key >> 3)
            let wireType = Int(key & 0x7)
            guard fieldNumber > 0 else {
                throw NativeAppleNotesParserError.invalidProtobuf("Invalid field number.")
            }

            switch wireType {
            case 0:
                _ = try reader.readVarint()
                fields.append(ProtobufField(number: fieldNumber, wireType: wireType, lengthDelimited: nil))
            case 1:
                try reader.skip(byteCount: 8)
                fields.append(ProtobufField(number: fieldNumber, wireType: wireType, lengthDelimited: nil))
            case 2:
                let length = Int(try reader.readVarint())
                let value = try reader.readData(byteCount: length)
                fields.append(ProtobufField(number: fieldNumber, wireType: wireType, lengthDelimited: value))
            case 5:
                try reader.skip(byteCount: 4)
                fields.append(ProtobufField(number: fieldNumber, wireType: wireType, lengthDelimited: nil))
            default:
                throw NativeAppleNotesParserError.invalidProtobuf("Unsupported protobuf wire type \(wireType).")
            }
        }

        return fields
    }
}

private struct ProtobufReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(data: Data) {
        self.bytes = Array(data)
    }

    var isAtEnd: Bool {
        offset >= bytes.count
    }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while shift < 64 {
            guard offset < bytes.count else {
                throw NativeAppleNotesParserError.invalidProtobuf("Unexpected end of varint.")
            }
            let byte = bytes[offset]
            offset += 1
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
        }

        throw NativeAppleNotesParserError.invalidProtobuf("Varint is too long.")
    }

    mutating func readData(byteCount: Int) throws -> Data {
        guard byteCount >= 0, offset + byteCount <= bytes.count else {
            throw NativeAppleNotesParserError.invalidProtobuf("Length-delimited field exceeds available data.")
        }
        let value = Data(bytes[offset..<(offset + byteCount)])
        offset += byteCount
        return value
    }

    mutating func skip(byteCount: Int) throws {
        _ = try readData(byteCount: byteCount)
    }
}
