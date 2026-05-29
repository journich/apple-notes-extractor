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
            let databaseURL = appleNotesDatabaseURL(databasePath: databasePath, notesContainerPath: notesContainerPath)
            let inspection = try AppleNotesSchemaInspector(fileManager: fileManager).inspect(databaseURL: databaseURL)
            output(SchemaInspectionFormatter().format(inspection))
        case .accounts(let databasePath, let notesContainerPath):
            let inventory = try readInventory(databasePath: databasePath, notesContainerPath: notesContainerPath)
            output(AppleNotesInventoryFormatter().formatAccounts(inventory.accounts))
        case .folders(let accountName, let databasePath, let notesContainerPath):
            let inventory = try readInventory(databasePath: databasePath, notesContainerPath: notesContainerPath)
            output(try AppleNotesInventoryFormatter().formatFolders(
                inventory.folders,
                accounts: inventory.accounts,
                accountName: accountName
            ))
        case .notes(let accountName, let folderPath, let recursive, let databasePath, let notesContainerPath):
            let inventory = try readInventory(databasePath: databasePath, notesContainerPath: notesContainerPath)
            output(try AppleNotesInventoryFormatter().formatNotes(
                inventory.notes,
                folders: inventory.folders,
                accounts: inventory.accounts,
                accountName: accountName,
                folderPath: folderPath,
                recursive: recursive
            ))
        case .resolveScope(let accountName, let folderPath, let recursive, let databasePath, let notesContainerPath):
            let inventory = try readInventory(databasePath: databasePath, notesContainerPath: notesContainerPath)
            let resolution = try AppleNotesScopeResolver().resolve(
                AppleNotesScopeRequest(accountName: accountName, folderPath: folderPath, recursive: recursive),
                inventory: inventory
            )
            output(ScopeResolutionFormatter().format(resolution))
        case .status(let stateDatabasePath):
            let url = stateDatabaseURL(stateDatabasePath)
            let stateDatabase = try StateDatabase.open(at: url)
            try stateDatabase.migrate()
            output(StateDatabaseFormatter().formatStatus(try stateDatabase.status(), path: url.path))
        case .resetState(let noteUUID, let stateDatabasePath):
            let url = stateDatabaseURL(stateDatabasePath)
            let stateDatabase = try StateDatabase.open(at: url)
            try stateDatabase.migrate()
            try stateDatabase.resetNoteState(noteUUID: noteUUID)
            output("Reset state for note: \(noteUUID)")
        case .scan(let accountName, let folderPath, let recursive, let databasePath, let notesContainerPath, let stateDatabasePath):
            let stateDatabase = try StateDatabase.open(at: stateDatabaseURL(stateDatabasePath))
            let summary = try ScanEngine(stateDatabase: stateDatabase).scan(
                databaseURL: appleNotesDatabaseURL(databasePath: databasePath, notesContainerPath: notesContainerPath),
                scopeRequest: AppleNotesScopeRequest(accountName: accountName, folderPath: folderPath, recursive: recursive),
                missingGraceCount: AppConfig.defaultConfig.polling.missingScanGraceCount
            )
            output(ScanSummaryFormatter().format(summary))
        }
    }

    private func readInventory(databasePath: String?, notesContainerPath: String?) throws -> AppleNotesInventory {
        let databaseURL = appleNotesDatabaseURL(databasePath: databasePath, notesContainerPath: notesContainerPath)
        return try AppleNotesInventoryReader(fileManager: fileManager).readInventory(databaseURL: databaseURL)
    }

    private func appleNotesDatabaseURL(databasePath: String?, notesContainerPath: String?) -> URL {
        let paths = AppPaths(fileManager: fileManager, environment: environment)

        if let databasePath {
            return paths.expandPath(databasePath).standardizedFileURL
        }

        if let notesContainerPath {
            return paths
                .expandPath(notesContainerPath)
                .appendingPathComponent("NoteStore.sqlite")
                .standardizedFileURL
        }

        return AppleNotesPaths(paths: paths).noteStoreDatabaseURL
    }

    private func stateDatabaseURL(_ path: String?) -> URL {
        let paths = AppPaths(fileManager: fileManager, environment: environment)
        return paths.expandPath(path ?? AppConfig.defaultConfig.paths.stateDatabase).standardizedFileURL
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
      notes2myicor accounts [--database <path>] [--notes-container <path>]
      notes2myicor folders [--account <name>] [--database <path>] [--notes-container <path>]
      notes2myicor notes [--account <name>] [--folder <path>] [--recursive] [--database <path>] [--notes-container <path>]
      notes2myicor resolve-scope --account <name> --folder <path> [--recursive] [--database <path>] [--notes-container <path>]
      notes2myicor status [--state-db <path>]
      notes2myicor reset-state --note-uuid <uuid> [--state-db <path>]
      notes2myicor scan --account <name> --folder <path> [--recursive] [--database <path>] [--notes-container <path>] [--state-db <path>]

    Commands:
      accounts         List Apple Notes accounts.
      folders          List Apple Notes folders.
      init             Create a default JSON config file.
      inspect-schema   Inspect the local Apple Notes SQLite schema read-only.
      notes            List Apple Notes note metadata.
      reset-state      Remove one note from the local app state database.
      resolve-scope    Resolve an account and folder path to allowed folder IDs.
      scan             Classify current notes against local state without exporting.
      status           Print local app state database status.
      version          Print the application version.

    Options:
      --account           Apple Notes account name.
      --config            Config file path. Defaults to ~/Library/Application Support/Notes2MyICOR/config.json.
      --database          SQLite database path for schema inspection.
      --folder            Apple Notes folder path.
      --notes-container   Apple Notes group container path. Defaults to ~/Library/Group Containers/group.com.apple.notes.
      --note-uuid         Apple Notes note UUID.
      --recursive         Include subfolders when used with notes and --folder.
      --state-db          App-owned state database path.
      --force             Overwrite an existing config file when used with init.
      --help              Show this help.
    """
}

public enum CLICommand: Equatable, Sendable {
    case help
    case version
    case initConfig(configPath: String?, force: Bool)
    case inspectSchema(databasePath: String?, notesContainerPath: String?)
    case accounts(databasePath: String?, notesContainerPath: String?)
    case folders(accountName: String?, databasePath: String?, notesContainerPath: String?)
    case notes(accountName: String?, folderPath: String?, recursive: Bool, databasePath: String?, notesContainerPath: String?)
    case resolveScope(accountName: String, folderPath: String, recursive: Bool, databasePath: String?, notesContainerPath: String?)
    case status(stateDatabasePath: String?)
    case resetState(noteUUID: String, stateDatabasePath: String?)
    case scan(accountName: String, folderPath: String, recursive: Bool, databasePath: String?, notesContainerPath: String?, stateDatabasePath: String?)

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
        case "accounts":
            let options = try parseInventoryOptions(Array(arguments.dropFirst()), allowed: [.database, .notesContainer])
            return .accounts(databasePath: options.databasePath, notesContainerPath: options.notesContainerPath)
        case "folders":
            let options = try parseInventoryOptions(Array(arguments.dropFirst()), allowed: [.account, .database, .notesContainer])
            return .folders(accountName: options.accountName, databasePath: options.databasePath, notesContainerPath: options.notesContainerPath)
        case "notes":
            let options = try parseInventoryOptions(Array(arguments.dropFirst()), allowed: [.account, .folder, .recursive, .database, .notesContainer])
            return .notes(
                accountName: options.accountName,
                folderPath: options.folderPath,
                recursive: options.recursive,
                databasePath: options.databasePath,
                notesContainerPath: options.notesContainerPath
            )
        case "resolve-scope":
            let options = try parseInventoryOptions(Array(arguments.dropFirst()), allowed: [.account, .folder, .recursive, .database, .notesContainer])
            guard let accountName = options.accountName else {
                throw CLIError.usage("Missing required option: --account")
            }
            guard let folderPath = options.folderPath else {
                throw CLIError.usage("Missing required option: --folder")
            }
            return .resolveScope(
                accountName: accountName,
                folderPath: folderPath,
                recursive: options.recursive,
                databasePath: options.databasePath,
                notesContainerPath: options.notesContainerPath
            )
        case "status":
            let options = try parseStateOptions(Array(arguments.dropFirst()), requiresNoteUUID: false)
            return .status(stateDatabasePath: options.stateDatabasePath)
        case "reset-state":
            let options = try parseStateOptions(Array(arguments.dropFirst()), requiresNoteUUID: true)
            guard let noteUUID = options.noteUUID else {
                throw CLIError.usage("Missing required option: --note-uuid")
            }
            return .resetState(noteUUID: noteUUID, stateDatabasePath: options.stateDatabasePath)
        case "scan":
            let options = try parseInventoryOptions(Array(arguments.dropFirst()), allowed: [.account, .folder, .recursive, .database, .notesContainer, .stateDatabase])
            guard let accountName = options.accountName else {
                throw CLIError.usage("Missing required option: --account")
            }
            guard let folderPath = options.folderPath else {
                throw CLIError.usage("Missing required option: --folder")
            }
            return .scan(
                accountName: accountName,
                folderPath: folderPath,
                recursive: options.recursive,
                databasePath: options.databasePath,
                notesContainerPath: options.notesContainerPath,
                stateDatabasePath: options.stateDatabasePath
            )
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

    private static func parseInventoryOptions(_ arguments: [String], allowed: Set<InventoryOption>) throws -> InventoryOptions {
        var options = InventoryOptions()
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--account":
                try requireAllowed(.account, in: allowed, argument: argument)
                options.accountName = try requireValue(iterator.next(), for: argument)
            case "--folder":
                try requireAllowed(.folder, in: allowed, argument: argument)
                options.folderPath = try requireValue(iterator.next(), for: argument)
            case "--recursive":
                try requireAllowed(.recursive, in: allowed, argument: argument)
                options.recursive = true
            case "--database":
                try requireAllowed(.database, in: allowed, argument: argument)
                options.databasePath = try requireValue(iterator.next(), for: argument)
            case "--notes-container":
                try requireAllowed(.notesContainer, in: allowed, argument: argument)
                options.notesContainerPath = try requireValue(iterator.next(), for: argument)
            case "--state-db":
                try requireAllowed(.stateDatabase, in: allowed, argument: argument)
                options.stateDatabasePath = try requireValue(iterator.next(), for: argument)
            case "--help", "-h":
                throw CLIError.usage(AppRunner.helpText)
            default:
                throw CLIError.usage("Unknown option: \(argument)")
            }
        }

        return options
    }

    private static func parseStateOptions(_ arguments: [String], requiresNoteUUID: Bool) throws -> StateOptions {
        var options = StateOptions()
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--state-db":
                options.stateDatabasePath = try requireValue(iterator.next(), for: argument)
            case "--note-uuid":
                options.noteUUID = try requireValue(iterator.next(), for: argument)
            case "--help", "-h":
                throw CLIError.usage(AppRunner.helpText)
            default:
                throw CLIError.usage("Unknown option: \(argument)")
            }
        }

        if requiresNoteUUID, options.noteUUID == nil {
            throw CLIError.usage("Missing required option: --note-uuid")
        }

        return options
    }

    private static func requireAllowed(_ option: InventoryOption, in allowed: Set<InventoryOption>, argument: String) throws {
        guard allowed.contains(option) else {
            throw CLIError.usage("Unsupported option for this command: \(argument)")
        }
    }

    private static func requireValue(_ value: String?, for argument: String) throws -> String {
        guard let value, value.hasPrefix("--") == false else {
            throw CLIError.usage("Missing value for \(argument)")
        }
        return value
    }
}

private struct InventoryOptions {
    var accountName: String?
    var folderPath: String?
    var recursive = false
    var databasePath: String?
    var notesContainerPath: String?
    var stateDatabasePath: String?
}

private struct StateOptions {
    var noteUUID: String?
    var stateDatabasePath: String?
}

private enum InventoryOption: Hashable {
    case account
    case folder
    case recursive
    case database
    case notesContainer
    case stateDatabase
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
