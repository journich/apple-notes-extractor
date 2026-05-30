import Foundation

public struct AppConfig: Codable, Equatable, Sendable {
    public var scope: Scope
    public var paths: Paths
    public var polling: Polling
    public var export: Export
    public var parser: Parser

    public init(
        scope: Scope = Scope(),
        paths: Paths = Paths(),
        polling: Polling = Polling(),
        export: Export = Export(),
        parser: Parser = Parser()
    ) {
        self.scope = scope
        self.paths = paths
        self.polling = polling
        self.export = export
        self.parser = parser
    }

    public static let defaultConfig = AppConfig()
}

public extension AppConfig {
    struct Scope: Codable, Equatable, Sendable {
        public var accountName: String
        public var folderPath: String
        public var recursive: Bool
        public var includeRecentlyDeleted: Bool

        public init(
            accountName: String = "iCloud",
            folderPath: String = "Apple Notes Export",
            recursive: Bool = true,
            includeRecentlyDeleted: Bool = false
        ) {
            self.accountName = accountName
            self.folderPath = folderPath
            self.recursive = recursive
            self.includeRecentlyDeleted = includeRecentlyDeleted
        }
    }

    struct Paths: Codable, Equatable, Sendable {
        public var notesGroupContainer: String
        public var outputDirectory: String
        public var stateDatabase: String
        public var workDirectory: String
        public var logDirectory: String

        public init(
            notesGroupContainer: String = "~/Library/Group Containers/group.com.apple.notes",
            outputDirectory: String = "~/Notes2MyICOR/Apple Notes",
            stateDatabase: String = "~/Library/Application Support/Notes2MyICOR/state.sqlite",
            workDirectory: String = "~/Library/Application Support/Notes2MyICOR/work",
            logDirectory: String = "~/Library/Logs/Notes2MyICOR"
        ) {
            self.notesGroupContainer = notesGroupContainer
            self.outputDirectory = outputDirectory
            self.stateDatabase = stateDatabase
            self.workDirectory = workDirectory
            self.logDirectory = logDirectory
        }
    }

    struct Polling: Codable, Equatable, Sendable {
        public var intervalSeconds: Int
        public var fullInventoryEveryRuns: Int
        public var missingScanGraceCount: Int

        public init(
            intervalSeconds: Int = 300,
            fullInventoryEveryRuns: Int = 12,
            missingScanGraceCount: Int = 3
        ) {
            self.intervalSeconds = intervalSeconds
            self.fullInventoryEveryRuns = fullInventoryEveryRuns
            self.missingScanGraceCount = missingScanGraceCount
        }
    }

    struct Export: Codable, Equatable, Sendable {
        public var writeSidecarJSON: Bool
        public var mirrorFolderTree: Bool
        public var filenameStrategy: String
        public var renderFormat: String
        public var appendEmbeddedPDFs: Bool
        public var neverDeleteExportedPDFs: Bool

        public init(
            writeSidecarJSON: Bool = true,
            mirrorFolderTree: Bool = true,
            filenameStrategy: String = "uuid-title",
            renderFormat: String = "A4",
            appendEmbeddedPDFs: Bool = true,
            neverDeleteExportedPDFs: Bool = true
        ) {
            self.writeSidecarJSON = writeSidecarJSON
            self.mirrorFolderTree = mirrorFolderTree
            self.filenameStrategy = filenameStrategy
            self.renderFormat = renderFormat
            self.appendEmbeddedPDFs = appendEmbeddedPDFs
            self.neverDeleteExportedPDFs = neverDeleteExportedPDFs
        }
    }

    struct Parser: Codable, Equatable, Sendable {
        public var mode: String
        public var appleCloudNotesParserPath: String?

        public init(
            mode: String = "apple-cloud-notes-parser",
            appleCloudNotesParserPath: String? = nil
        ) {
            self.mode = mode
            self.appleCloudNotesParserPath = appleCloudNotesParserPath
        }
    }
}

public enum ConfigError: Error, Equatable, LocalizedError {
    case missing(URL)
    case invalid(URL, String)
    case alreadyExists(URL)

    public var errorDescription: String? {
        switch self {
        case .missing(let url):
            "Config file not found: \(url.path)"
        case .invalid(let url, let reason):
            "Invalid config file at \(url.path): \(reason)"
        case .alreadyExists(let url):
            "Config file already exists: \(url.path)"
        }
    }
}

public struct ConfigStore {
    public let fileManager: FileManager
    public let encoder: JSONEncoder
    public let decoder: JSONDecoder

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func load(from url: URL) throws -> AppConfig {
        guard fileManager.fileExists(atPath: url.path) else {
            throw ConfigError.missing(url)
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(AppConfig.self, from: data)
        } catch let error as DecodingError {
            throw ConfigError.invalid(url, String(describing: error))
        } catch {
            throw ConfigError.invalid(url, error.localizedDescription)
        }
    }

    public func writeDefaultConfig(to url: URL, overwrite: Bool = false) throws {
        if fileManager.fileExists(atPath: url.path), overwrite == false {
            throw ConfigError.alreadyExists(url)
        }

        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(AppConfig.defaultConfig)
        try data.write(to: url, options: [.atomic])
    }
}
