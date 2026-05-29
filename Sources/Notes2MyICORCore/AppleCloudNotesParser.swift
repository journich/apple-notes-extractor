import Foundation

public struct AppleCloudNotesParserConfig: Equatable, Sendable {
    public var rubyExecutablePath: String
    public var parserScriptPath: String
    public var outputDirectory: URL

    public init(rubyExecutablePath: String, parserScriptPath: String, outputDirectory: URL) {
        self.rubyExecutablePath = rubyExecutablePath
        self.parserScriptPath = parserScriptPath
        self.outputDirectory = outputDirectory
    }
}

public protocol NoteParsing {
    func parse(notesContainer: URL, noteUUIDs: [String]) throws -> AppleCloudNotesParserResult
}

public struct ExternalCommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol ExternalCommandRunning {
    func run(executablePath: String, arguments: [String], workingDirectory: URL?) throws -> ExternalCommandResult
}

public struct ProcessCommandRunner: ExternalCommandRunning {
    public init() {}

    public func run(executablePath: String, arguments: [String], workingDirectory: URL?) throws -> ExternalCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

        return ExternalCommandResult(
            exitCode: process.terminationStatus,
            standardOutput: String(data: outputData, encoding: .utf8) ?? "",
            standardError: String(data: errorData, encoding: .utf8) ?? ""
        )
    }
}

public struct AppleCloudNotesParsedNote: Equatable, Sendable {
    public var uuid: String
    public var title: String
    public var html: String
    public var jsonID: String
    public var individualHTMLPath: String?

    public init(uuid: String, title: String, html: String, jsonID: String, individualHTMLPath: String?) {
        self.uuid = uuid
        self.title = title
        self.html = html
        self.jsonID = jsonID
        self.individualHTMLPath = individualHTMLPath
    }
}

public struct AppleCloudNotesParserResult: Equatable, Sendable {
    public var outputDirectory: URL
    public var jsonPath: URL
    public var notes: [AppleCloudNotesParsedNote]
    public var standardOutput: String
    public var standardError: String

    public init(
        outputDirectory: URL,
        jsonPath: URL,
        notes: [AppleCloudNotesParsedNote],
        standardOutput: String,
        standardError: String
    ) {
        self.outputDirectory = outputDirectory
        self.jsonPath = jsonPath
        self.notes = notes
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public enum AppleCloudNotesParserError: Error, Equatable, LocalizedError {
    case missingParserScript(String)
    case parserFailed(exitCode: Int32, standardError: String)
    case jsonOutputMissing(String)
    case invalidJSON(String)
    case noteNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .missingParserScript(let path):
            "Apple Cloud Notes Parser script not found: \(path)"
        case .parserFailed(let exitCode, let standardError):
            "Apple Cloud Notes Parser failed with exit code \(exitCode): \(standardError)"
        case .jsonOutputMissing(let path):
            "Apple Cloud Notes Parser JSON output not found: \(path)"
        case .invalidJSON(let reason):
            "Apple Cloud Notes Parser JSON could not be decoded: \(reason)"
        case .noteNotFound(let uuid):
            "Apple Cloud Notes Parser output did not contain note UUID: \(uuid)"
        }
    }
}

public struct AppleCloudNotesParser {
    public let config: AppleCloudNotesParserConfig
    public let runner: ExternalCommandRunning
    public let fileManager: FileManager

    public init(
        config: AppleCloudNotesParserConfig,
        runner: ExternalCommandRunning = ProcessCommandRunner(),
        fileManager: FileManager = .default
    ) {
        self.config = config
        self.runner = runner
        self.fileManager = fileManager
    }

    public func parse(notesContainer: URL, noteUUIDs: [String] = []) throws -> AppleCloudNotesParserResult {
        guard fileManager.fileExists(atPath: config.parserScriptPath) else {
            throw AppleCloudNotesParserError.missingParserScript(config.parserScriptPath)
        }

        try fileManager.createDirectory(at: config.outputDirectory, withIntermediateDirectories: true)

        let arguments = [
            config.parserScriptPath,
            "--mac",
            notesContainer.path,
            "--output-dir",
            config.outputDirectory.path,
            "--one-output-folder",
            "--individual-files",
            "--uuid",
            "--retain-display-order",
        ]

        let result = try runner.run(
            executablePath: config.rubyExecutablePath,
            arguments: arguments,
            workingDirectory: URL(fileURLWithPath: config.parserScriptPath).deletingLastPathComponent()
        )

        guard result.exitCode == 0 else {
            throw AppleCloudNotesParserError.parserFailed(exitCode: result.exitCode, standardError: result.standardError)
        }

        let jsonPath = config.outputDirectory
            .appendingPathComponent("notes_rip", isDirectory: true)
            .appendingPathComponent("json", isDirectory: true)
            .appendingPathComponent("all_notes_1.json")

        let notes = try AppleCloudNotesJSONDecoder(fileManager: fileManager).decodeNotes(
            jsonPath: jsonPath,
            outputDirectory: config.outputDirectory.appendingPathComponent("notes_rip", isDirectory: true),
            noteUUIDs: Set(noteUUIDs)
        )

        return AppleCloudNotesParserResult(
            outputDirectory: config.outputDirectory,
            jsonPath: jsonPath,
            notes: notes,
            standardOutput: result.standardOutput,
            standardError: result.standardError
        )
    }
}

extension AppleCloudNotesParser: NoteParsing {}

public struct AppleCloudNotesJSONDecoder {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func decodeNotes(jsonPath: URL, outputDirectory: URL, noteUUIDs: Set<String>) throws -> [AppleCloudNotesParsedNote] {
        guard fileManager.fileExists(atPath: jsonPath.path) else {
            throw AppleCloudNotesParserError.jsonOutputMissing(jsonPath.path)
        }

        let data = try Data(contentsOf: jsonPath)
        let object = try JSONSerialization.jsonObject(with: data)

        guard let root = object as? [String: Any],
              let noteObjects = root["notes"] as? [String: Any] else {
            throw AppleCloudNotesParserError.invalidJSON("Missing root notes dictionary")
        }

        let htmlPathsByUUID = findIndividualHTMLPaths(outputDirectory: outputDirectory)
        let notes = noteObjects.compactMap { jsonID, value -> AppleCloudNotesParsedNote? in
            guard let note = value as? [String: Any],
                  let uuid = note["uuid"] as? String else {
                return nil
            }

            if noteUUIDs.isEmpty == false && noteUUIDs.contains(uuid) == false {
                return nil
            }

            return AppleCloudNotesParsedNote(
                uuid: uuid,
                title: note["title"] as? String ?? "",
                html: note["html"] as? String ?? "",
                jsonID: jsonID,
                individualHTMLPath: htmlPathsByUUID[uuid]?.path
            )
        }

        for uuid in noteUUIDs where notes.contains(where: { $0.uuid == uuid }) == false {
            throw AppleCloudNotesParserError.noteNotFound(uuid)
        }

        return notes.sorted { $0.uuid < $1.uuid }
    }

    private func findIndividualHTMLPaths(outputDirectory: URL) -> [String: URL] {
        let htmlDirectory = outputDirectory.appendingPathComponent("html", isDirectory: true)
        guard let enumerator = fileManager.enumerator(at: htmlDirectory, includingPropertiesForKeys: nil) else {
            return [:]
        }

        var result: [String: URL] = [:]
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "html" {
            let uuid = fileURL.deletingPathExtension().lastPathComponent
            result[uuid] = fileURL
        }
        return result
    }
}

public struct AppleCloudNotesParserFormatter {
    public init() {}

    public func format(
        _ result: AppleCloudNotesParserResult,
        documents: [NoteDocument] = [],
        debugHTMLURLs: [URL] = []
    ) -> String {
        let documentLine = documents.isEmpty ? "" : "\nNote documents: \(documents.count)"
        let debugLine = debugHTMLURLs.isEmpty ? "" : "\nDebug HTML files: \(debugHTMLURLs.count)"
        return """
        Apple Cloud Notes Parser result:
        Output directory: \(result.outputDirectory.path)
        JSON: \(result.jsonPath.path)
        Parsed notes: \(result.notes.count)
        \(documentLine)\(debugLine)
        """
    }
}
