import Foundation

public struct AppRunner {
    public let fileManager: FileManager
    public let environment: [String: String]
    public let output: @Sendable (String) -> Void
    public let errorOutput: @Sendable (String) -> Void

    public init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        output: @escaping @Sendable (String) -> Void = { print($0) },
        errorOutput: @escaping @Sendable (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.output = output
        self.errorOutput = errorOutput
    }

    @discardableResult
    public func run(arguments: [String]) -> Int {
        do {
            let command = try CLICommand.parse(arguments)
            try run(command)
            return 0
        } catch let error as CLIError {
            errorOutput(error.message)
            return error.exitCode
        } catch {
            errorOutput(error.localizedDescription)
            return 1
        }
    }

    private func run(_ command: CLICommand) throws {
        switch command {
        case .help:
            output(Self.helpText)
        case .version:
            output(AppVersion.current)
        case .initConfig(let configPath, let force):
            let paths = AppPaths(fileManager: fileManager, environment: environment)
            let url = paths.expandPath(configPath ?? paths.defaultConfigPath).standardizedFileURL
            try ConfigStore(fileManager: fileManager).writeDefaultConfig(to: url, overwrite: force)
            output("Created config: \(url.path)")
        case .inspectSchema(let databasePath, let notesContainerPath):
            let paths = AppPaths(fileManager: fileManager, environment: environment)
            let databaseURL: URL

            if let databasePath {
                databaseURL = paths.expandPath(databasePath).standardizedFileURL
            } else if let notesContainerPath {
                databaseURL = paths
                    .expandPath(notesContainerPath)
                    .appendingPathComponent("NoteStore.sqlite")
                    .standardizedFileURL
            } else {
                databaseURL = AppleNotesPaths(paths: paths).noteStoreDatabaseURL
            }

            let inspection = try AppleNotesSchemaInspector(fileManager: fileManager).inspect(databaseURL: databaseURL)
            output(SchemaInspectionFormatter().format(inspection))
        }
    }
}

public extension AppRunner {
    static let helpText = """
    notes2myicor

    Usage:
      notes2myicor --help
      notes2myicor version
      notes2myicor init [--config <path>] [--force]
      notes2myicor inspect-schema [--database <path>] [--notes-container <path>]

    Commands:
      init             Create a default JSON config file.
      inspect-schema   Inspect the local Apple Notes SQLite schema read-only.
      version          Print the application version.

    Options:
      --config            Config file path. Defaults to ~/Library/Application Support/Notes2MyICOR/config.json.
      --database          SQLite database path for schema inspection.
      --notes-container   Apple Notes group container path. Defaults to ~/Library/Group Containers/group.com.apple.notes.
      --force             Overwrite an existing config file when used with init.
      --help              Show this help.
    """
}

public enum CLICommand: Equatable, Sendable {
    case help
    case version
    case initConfig(configPath: String?, force: Bool)
    case inspectSchema(databasePath: String?, notesContainerPath: String?)

    public static func parse(_ arguments: [String]) throws -> CLICommand {
        guard let first = arguments.first else {
            return .help
        }

        switch first {
        case "--help", "-h", "help":
            return .help
        case "version", "--version":
            return .version
        case "init":
            return try parseInit(Array(arguments.dropFirst()))
        case "inspect-schema":
            return try parseInspectSchema(Array(arguments.dropFirst()))
        default:
            throw CLIError.usage("Unknown command: \(first)")
        }
    }

    private static func parseInit(_ arguments: [String]) throws -> CLICommand {
        var configPath: String?
        var force = false
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--config":
                guard let value = iterator.next(), value.hasPrefix("--") == false else {
                    throw CLIError.usage("Missing value for --config")
                }
                configPath = value
            case "--force":
                force = true
            case "--help", "-h":
                return .help
            default:
                throw CLIError.usage("Unknown init option: \(argument)")
            }
        }

        return .initConfig(configPath: configPath, force: force)
    }

    private static func parseInspectSchema(_ arguments: [String]) throws -> CLICommand {
        var databasePath: String?
        var notesContainerPath: String?
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--database":
                guard let value = iterator.next(), value.hasPrefix("--") == false else {
                    throw CLIError.usage("Missing value for --database")
                }
                databasePath = value
            case "--notes-container":
                guard let value = iterator.next(), value.hasPrefix("--") == false else {
                    throw CLIError.usage("Missing value for --notes-container")
                }
                notesContainerPath = value
            case "--help", "-h":
                return .help
            default:
                throw CLIError.usage("Unknown inspect-schema option: \(argument)")
            }
        }

        return .inspectSchema(databasePath: databasePath, notesContainerPath: notesContainerPath)
    }
}

public enum CLIError: Error, Equatable, Sendable {
    case usage(String)

    public var message: String {
        switch self {
        case .usage(let message):
            "\(message)\n\n\(AppRunner.helpText)"
        }
    }

    public var exitCode: Int {
        switch self {
        case .usage:
            2
        }
    }
}

public enum AppVersion {
    public static let current = "0.1.0-dev"
}
