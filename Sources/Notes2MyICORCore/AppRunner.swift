import Foundation

public struct AppRunner {
    public let fileManager: FileManager
    public let environment: [String: String]
    public let pdfRenderer: PDFRendering
    public let sleep: @Sendable (TimeInterval) -> Void
    public let output: @Sendable (String) -> Void
    public let errorOutput: @Sendable (String) -> Void

    public init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        pdfRenderer: PDFRendering = WebKitPDFRenderer(),
        sleep: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        output: @escaping @Sendable (String) -> Void = { print($0) },
        errorOutput: @escaping @Sendable (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.pdfRenderer = pdfRenderer
        self.sleep = sleep
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
        case .snapshot(let notesContainerPath, let workDirectoryPath):
            let paths = AppPaths(fileManager: fileManager, environment: environment)
            let source = notesContainerPath.map { paths.expandPath($0).standardizedFileURL }
                ?? AppleNotesPaths(paths: paths).groupContainerURL
            let work = paths.expandPath(workDirectoryPath ?? AppConfig.defaultConfig.paths.workDirectory).standardizedFileURL
            let snapshot = try AppleNotesSnapshotter(fileManager: fileManager).createSnapshot(
                sourceContainer: source,
                workDirectory: work
            )
            output(SnapshotFormatter().format(snapshot))
        case .parse(let noteUUID, let databasePath, let notesContainerPath, let parserMode, let parserScriptPath, let rubyPath, let outputDirectoryPath, let debugHTMLDirectoryPath):
            let paths = AppPaths(fileManager: fileManager, environment: environment)
            let source = notesContainerPath.map { paths.expandPath($0).standardizedFileURL }
                ?? AppleNotesPaths(paths: paths).groupContainerURL
            let outputDirectory = paths.expandPath(outputDirectoryPath ?? "~/Library/Application Support/Notes2MyICOR/acnp-output").standardizedFileURL
            let parser = noteParser(
                parserMode: parserMode,
                databasePath: databasePath,
                notesContainerPath: source.path,
                parserScriptPath: parserScriptPath,
                rubyPath: rubyPath,
                parserOutputDirectory: outputDirectory
            )
            let result = try parser.parse(notesContainer: source, noteUUIDs: noteUUID.map { [$0] } ?? [])
            let documents = result.notes.map { NoteDocumentBuilder().document(parsedNote: $0) }
            let debugHTMLURLs: [URL]
            if let debugHTMLDirectoryPath {
                let debugHTMLDirectory = paths.expandPath(debugHTMLDirectoryPath).standardizedFileURL
                debugHTMLURLs = try NoteDocumentDebugHTMLWriter().write(documents, to: debugHTMLDirectory)
            } else {
                debugHTMLURLs = []
            }
            output(AppleCloudNotesParserFormatter().format(result, documents: documents, debugHTMLURLs: debugHTMLURLs))
        case .export(let noteUUID, let title, let htmlPath, let accountName, let folderPath, let notesContainerPath, let parserScriptPath, let rubyPath, let parserOutputDirectoryPath, let outputDirectoryPath, let writeDebugHTML):
            let paths = AppPaths(fileManager: fileManager, environment: environment)
            let outputDirectory = paths.expandPath(outputDirectoryPath ?? AppConfig.defaultConfig.paths.outputDirectory).standardizedFileURL
            let document: NoteDocument
            if let htmlPath {
                let htmlURL = paths.expandPath(htmlPath).standardizedFileURL
                let html = try String(contentsOf: htmlURL, encoding: .utf8)
                let assets = NoteDocumentAssetResolver().resolveAssets(html: html, htmlPath: htmlURL.path)
                let embeddedObjects = NoteDocumentEmbeddedObjectDetector().detect(html: html, assets: assets)
                document = NoteDocument(
                    uuid: noteUUID,
                    title: title ?? htmlURL.deletingPathExtension().lastPathComponent,
                    accountName: accountName,
                    folderPath: folderPath,
                    createdAt: nil,
                    modifiedAt: nil,
                    htmlPath: htmlURL.path,
                    htmlContent: html,
                    assets: assets,
                    embeddedObjects: embeddedObjects,
                    warnings: NoteDocumentEmbeddedObjectDetector().warnings(for: embeddedObjects)
                )
            } else {
                let source = notesContainerPath.map { paths.expandPath($0).standardizedFileURL }
                    ?? AppleNotesPaths(paths: paths).groupContainerURL
                let parserOutputDirectory = paths.expandPath(parserOutputDirectoryPath ?? "~/Library/Application Support/Notes2MyICOR/acnp-output").standardizedFileURL
                let parser = AppleCloudNotesParser(config: AppleCloudNotesParserConfig(
                    rubyExecutablePath: rubyPath ?? "/opt/homebrew/opt/ruby/bin/ruby",
                    parserScriptPath: parserScriptPath ?? "../apple_cloud_notes_parser/notes_cloud_ripper.rb",
                    outputDirectory: parserOutputDirectory
                ))
                let result = try parser.parse(notesContainer: source, noteUUIDs: [noteUUID])
                guard let parsedNote = result.notes.first else {
                    throw AppleCloudNotesParserError.noteNotFound(noteUUID)
                }
                document = NoteDocumentBuilder().document(
                    parsedNote: parsedNote,
                    accountName: accountName,
                    folderPath: folderPath
                )
            }

            let result = try NoteExporter(pdfRenderer: pdfRenderer).export(
                document: document,
                options: NoteExportOptions(
                    outputDirectory: outputDirectory,
                    mirrorFolderTree: AppConfig.defaultConfig.export.mirrorFolderTree,
                    writeSidecarJSON: AppConfig.defaultConfig.export.writeSidecarJSON,
                    writeDebugHTML: writeDebugHTML,
                    embeddedPDFMode: defaultEmbeddedPDFMode()
                )
            )
            output(NoteExportFormatter().format(result))
        case .syncOnce(let dryRun, let accountName, let folderPath, let recursive, let databasePath, let notesContainerPath, let parserMode, let parserScriptPath, let rubyPath, let parserOutputDirectoryPath, let outputDirectoryPath, let stateDatabasePath):
            let summary = try runSyncOnce(
                dryRun: dryRun,
                accountName: accountName,
                folderPath: folderPath,
                recursive: recursive,
                databasePath: databasePath,
                notesContainerPath: notesContainerPath,
                parserMode: parserMode,
                parserScriptPath: parserScriptPath,
                rubyPath: rubyPath,
                parserOutputDirectoryPath: parserOutputDirectoryPath,
                outputDirectoryPath: outputDirectoryPath,
                stateDatabasePath: stateDatabasePath
            )
            output(SyncSummaryFormatter().format(summary))
        case .syncWatch(let dryRun, let accountName, let folderPath, let recursive, let databasePath, let notesContainerPath, let parserMode, let parserScriptPath, let rubyPath, let parserOutputDirectoryPath, let outputDirectoryPath, let stateDatabasePath, let intervalSeconds, let maxRuns):
            var completedRuns = 0
            while maxRuns == nil || completedRuns < (maxRuns ?? 0) {
                let summary = try runSyncOnce(
                    dryRun: dryRun,
                    accountName: accountName,
                    folderPath: folderPath,
                    recursive: recursive,
                    databasePath: databasePath,
                    notesContainerPath: notesContainerPath,
                    parserMode: parserMode,
                    parserScriptPath: parserScriptPath,
                    rubyPath: rubyPath,
                    parserOutputDirectoryPath: parserOutputDirectoryPath,
                    outputDirectoryPath: outputDirectoryPath,
                    stateDatabasePath: stateDatabasePath
                )
                completedRuns += 1
                output(SyncSummaryFormatter().format(summary))
                if maxRuns == nil || completedRuns < (maxRuns ?? 0) {
                    sleep(TimeInterval(intervalSeconds))
                }
            }
            if maxRuns != nil {
                output("Watch completed: runs=\(completedRuns)")
            }
        case .installLaunchAgent(let label, let binaryPath, let launchAgentsDirectoryPath, let logDirectoryPath, let intervalSeconds, let accountName, let folderPath, let recursive, let databasePath, let notesContainerPath, let parserMode, let parserScriptPath, let rubyPath, let parserOutputDirectoryPath, let outputDirectoryPath, let stateDatabasePath):
            let paths = AppPaths(fileManager: fileManager, environment: environment)
            let config = LaunchAgentConfig(
                label: label,
                executableURL: binaryPath.map { paths.expandPath($0).standardizedFileURL } ?? defaultExecutableURL(),
                syncArguments: launchAgentSyncArguments(
                    accountName: accountName,
                    folderPath: folderPath,
                    recursive: recursive,
                    databasePath: databasePath,
                    notesContainerPath: notesContainerPath,
                    parserMode: parserMode,
                    parserScriptPath: parserScriptPath,
                    rubyPath: rubyPath,
                    parserOutputDirectoryPath: parserOutputDirectoryPath,
                    outputDirectoryPath: outputDirectoryPath,
                    stateDatabasePath: stateDatabasePath
                ),
                intervalSeconds: intervalSeconds,
                standardOutURL: launchAgentLogURL(
                    logDirectoryPath: logDirectoryPath,
                    fileName: LaunchAgentDefaults.standardOutFileName
                ),
                standardErrorURL: launchAgentLogURL(
                    logDirectoryPath: logDirectoryPath,
                    fileName: LaunchAgentDefaults.standardErrorFileName
                )
            )
            let plistURL = try LaunchAgentManager(fileManager: fileManager).install(
                config,
                launchAgentsDirectory: launchAgentsDirectory(launchAgentsDirectoryPath)
            )
            output(LaunchAgentFormatter().formatInstalled(plistURL: plistURL))
        case .uninstallLaunchAgent(let label, let launchAgentsDirectoryPath):
            let plistURL = try LaunchAgentManager(fileManager: fileManager).uninstall(
                label: label,
                launchAgentsDirectory: launchAgentsDirectory(launchAgentsDirectoryPath)
            )
            output(LaunchAgentFormatter().formatUninstalled(plistURL: plistURL))
        case .launchAgentStatus(let label, let launchAgentsDirectoryPath):
            let status = try LaunchAgentManager(fileManager: fileManager).status(
                label: label,
                launchAgentsDirectory: launchAgentsDirectory(launchAgentsDirectoryPath)
            )
            output(LaunchAgentFormatter().formatStatus(status))
        }
    }

    private func runSyncOnce(
        dryRun: Bool,
        accountName: String?,
        folderPath: String?,
        recursive: Bool?,
        databasePath: String?,
        notesContainerPath: String?,
        parserMode: String?,
        parserScriptPath: String?,
        rubyPath: String?,
        parserOutputDirectoryPath: String?,
        outputDirectoryPath: String?,
        stateDatabasePath: String?
    ) throws -> SyncSummary {
        let paths = AppPaths(fileManager: fileManager, environment: environment)
        let notesContainer = notesContainerPath.map { paths.expandPath($0).standardizedFileURL }
            ?? AppleNotesPaths(paths: paths).groupContainerURL
        let parserOutputDirectory = paths.expandPath(parserOutputDirectoryPath ?? "~/Library/Application Support/Notes2MyICOR/acnp-output").standardizedFileURL
        let outputDirectory = paths.expandPath(outputDirectoryPath ?? AppConfig.defaultConfig.paths.outputDirectory).standardizedFileURL
        let stateURL = paths.expandPath(stateDatabasePath ?? AppConfig.defaultConfig.paths.stateDatabase).standardizedFileURL
        let stateDatabase = try StateDatabase.open(at: stateURL)
        let parser = noteParser(
            parserMode: parserMode,
            databasePath: databasePath,
            notesContainerPath: notesContainer.path,
            parserScriptPath: parserScriptPath,
            rubyPath: rubyPath,
            parserOutputDirectory: parserOutputDirectory
        )
        let engine = SyncEngine(
            stateDatabase: stateDatabase,
            parser: parser,
            exporter: NoteExporter(pdfRenderer: pdfRenderer)
        )
        return try engine.syncOnce(SyncRequest(
            databaseURL: appleNotesDatabaseURL(databasePath: databasePath, notesContainerPath: notesContainer.path),
            notesContainerURL: notesContainer,
            scopeRequest: AppleNotesScopeRequest(
                accountName: accountName ?? AppConfig.defaultConfig.scope.accountName,
                folderPath: folderPath ?? AppConfig.defaultConfig.scope.folderPath,
                recursive: recursive ?? AppConfig.defaultConfig.scope.recursive
            ),
            parserOutputDirectory: parserOutputDirectory,
            exportOptions: NoteExportOptions(
                outputDirectory: outputDirectory,
                mirrorFolderTree: AppConfig.defaultConfig.export.mirrorFolderTree,
                writeSidecarJSON: AppConfig.defaultConfig.export.writeSidecarJSON,
                writeDebugHTML: false,
                embeddedPDFMode: defaultEmbeddedPDFMode()
            ),
            missingGraceCount: AppConfig.defaultConfig.polling.missingScanGraceCount,
            dryRun: dryRun
        ))
    }

    private func noteParser(
        parserMode: String?,
        databasePath: String?,
        notesContainerPath: String?,
        parserScriptPath: String?,
        rubyPath: String?,
        parserOutputDirectory: URL
    ) -> any NoteParsing {
        switch parserMode ?? AppConfig.defaultConfig.parser.mode {
        case "native-swift":
            return NativeAppleNotesParser(config: NativeAppleNotesParserConfig(
                databaseURL: appleNotesDatabaseURL(databasePath: databasePath, notesContainerPath: notesContainerPath),
                outputDirectory: parserOutputDirectory
            ))
        default:
            return AppleCloudNotesParser(config: AppleCloudNotesParserConfig(
                rubyExecutablePath: rubyPath ?? "/opt/homebrew/opt/ruby/bin/ruby",
                parserScriptPath: parserScriptPath ?? "../apple_cloud_notes_parser/notes_cloud_ripper.rb",
                outputDirectory: parserOutputDirectory
            ))
        }
    }

    private func defaultEmbeddedPDFMode() -> EmbeddedPDFMode {
        EmbeddedPDFMode(
            configValue: AppConfig.defaultConfig.export.embeddedPDFMode,
            appendEmbeddedPDFs: AppConfig.defaultConfig.export.appendEmbeddedPDFs
        )
    }

    private func launchAgentSyncArguments(
        accountName: String?,
        folderPath: String?,
        recursive: Bool?,
        databasePath: String?,
        notesContainerPath: String?,
        parserMode: String?,
        parserScriptPath: String?,
        rubyPath: String?,
        parserOutputDirectoryPath: String?,
        outputDirectoryPath: String?,
        stateDatabasePath: String?
    ) -> [String] {
        var arguments = ["sync", "--once"]
        appendOption("--account", accountName, to: &arguments)
        appendOption("--folder", folderPath, to: &arguments)
        if recursive == true {
            arguments.append("--recursive")
        }
        appendOption("--database", databasePath, to: &arguments)
        appendOption("--notes-container", notesContainerPath, to: &arguments)
        appendOption("--parser-mode", parserMode, to: &arguments)
        appendOption("--parser-script", parserScriptPath, to: &arguments)
        appendOption("--ruby", rubyPath, to: &arguments)
        appendOption("--parser-output-dir", parserOutputDirectoryPath, to: &arguments)
        appendOption("--output-dir", outputDirectoryPath, to: &arguments)
        appendOption("--state-db", stateDatabasePath, to: &arguments)
        return arguments
    }

    private func appendOption(_ name: String, _ value: String?, to arguments: inout [String]) {
        guard let value else {
            return
        }
        arguments.append(name)
        arguments.append(value)
    }

    private func defaultExecutableURL() -> URL {
        if let executableURL = Bundle.main.executableURL {
            return executableURL.standardizedFileURL
        }
        return URL(fileURLWithPath: CommandLine.arguments.first ?? "notes2myicor").standardizedFileURL
    }

    private func launchAgentsDirectory(_ path: String?) -> URL {
        let paths = AppPaths(fileManager: fileManager, environment: environment)
        return paths.expandPath(path ?? "~/Library/LaunchAgents").standardizedFileURL
    }

    private func launchAgentLogURL(logDirectoryPath: String?, fileName: String) -> URL {
        let paths = AppPaths(fileManager: fileManager, environment: environment)
        return paths
            .expandPath(logDirectoryPath ?? AppConfig.defaultConfig.paths.logDirectory)
            .appendingPathComponent(fileName)
            .standardizedFileURL
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
      notes2myicor snapshot [--notes-container <path>] [--work-dir <path>]
      notes2myicor parse [--note-uuid <uuid>] [--parser-mode <mode>] [--database <path>] [--notes-container <path>] [--parser-script <path>] [--ruby <path>] [--output-dir <path>] [--debug-html-dir <path>]
      notes2myicor export --note-uuid <uuid> [--html <path>] [--title <title>] [--output-dir <path>] [--debug-html]
      notes2myicor sync --once [--dry-run] [--account <name>] [--folder <path>] [--recursive]
      notes2myicor sync --watch [--interval-seconds <seconds>] [--account <name>] [--folder <path>] [--recursive]
      notes2myicor install-launch-agent [--binary <path>] [--interval-seconds <seconds>] [--account <name>] [--folder <path>] [--recursive]
      notes2myicor uninstall-launch-agent [--label <label>]
      notes2myicor launch-agent-status [--label <label>]

    Commands:
      accounts         List Apple Notes accounts.
      export           Render one note document to PDF with sidecar JSON.
      folders          List Apple Notes folders.
      init             Create a default JSON config file.
      install-launch-agent
                       Write a LaunchAgent plist for scheduled sync.
      inspect-schema   Inspect the local Apple Notes SQLite schema read-only.
      launch-agent-status
                       Print whether the LaunchAgent plist is installed.
      notes            List Apple Notes note metadata.
      parse            Run Apple Cloud Notes Parser and decode its JSON output.
      reset-state      Remove one note from the local app state database.
      resolve-scope    Resolve an account and folder path to allowed folder IDs.
      scan             Classify current notes against local state without exporting.
      snapshot         Copy the Apple Notes store and asset folders into a work snapshot.
      sync             Run one full scan, parse, and export pass.
      status           Print local app state database status.
      uninstall-launch-agent
                       Remove the LaunchAgent plist.
      version          Print the application version.

    Options:
      --account           Apple Notes account name.
      --binary            Absolute executable path to write into the LaunchAgent plist.
      --config            Config file path. Defaults to ~/Library/Application Support/Notes2MyICOR/config.json.
      --database          SQLite database path for schema inspection.
      --debug-html-dir    Directory for rendered debug HTML output.
      --folder            Apple Notes folder path.
      --html              HTML file path for fixture or debug export input.
      --interval-seconds  Poll interval for sync --watch or LaunchAgent StartInterval.
      --label             LaunchAgent label. Defaults to com.journich.notes2myicor.
      --launch-agents-dir LaunchAgent plist directory. Defaults to ~/Library/LaunchAgents.
      --log-dir           LaunchAgent stdout/stderr log directory. Defaults to ~/Library/Logs/Notes2MyICOR.
      --max-runs          Stop sync --watch after this many runs. Intended for tests and diagnostics.
      --notes-container   Apple Notes group container path. Defaults to ~/Library/Group Containers/group.com.apple.notes.
      --note-uuid         Apple Notes note UUID.
      --output-dir        Parser output directory.
      --parser-mode       Parser mode: apple-cloud-notes-parser or native-swift.
      --parser-output-dir Parser work output directory when export invokes the parser.
      --parser-script     Apple Cloud Notes Parser notes_cloud_ripper.rb path.
      --recursive         Include subfolders when used with notes and --folder.
      --ruby              Ruby executable path for Apple Cloud Notes Parser.
      --state-db          App-owned state database path.
      --title             Note title for HTML fixture export input.
      --work-dir          Snapshot work directory.
      --debug-html        Write rendered debug HTML next to the PDF when used with export.
      --dry-run           Plan sync work without parsing, exporting, or updating state.
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
    case snapshot(notesContainerPath: String?, workDirectoryPath: String?)
    case parse(noteUUID: String?, databasePath: String?, notesContainerPath: String?, parserMode: String?, parserScriptPath: String?, rubyPath: String?, outputDirectoryPath: String?, debugHTMLDirectoryPath: String?)
    case export(noteUUID: String, title: String?, htmlPath: String?, accountName: String?, folderPath: String?, notesContainerPath: String?, parserScriptPath: String?, rubyPath: String?, parserOutputDirectoryPath: String?, outputDirectoryPath: String?, writeDebugHTML: Bool)
    case syncOnce(dryRun: Bool, accountName: String?, folderPath: String?, recursive: Bool?, databasePath: String?, notesContainerPath: String?, parserMode: String?, parserScriptPath: String?, rubyPath: String?, parserOutputDirectoryPath: String?, outputDirectoryPath: String?, stateDatabasePath: String?)
    case syncWatch(dryRun: Bool, accountName: String?, folderPath: String?, recursive: Bool?, databasePath: String?, notesContainerPath: String?, parserMode: String?, parserScriptPath: String?, rubyPath: String?, parserOutputDirectoryPath: String?, outputDirectoryPath: String?, stateDatabasePath: String?, intervalSeconds: Int, maxRuns: Int?)
    case installLaunchAgent(label: String, binaryPath: String?, launchAgentsDirectoryPath: String?, logDirectoryPath: String?, intervalSeconds: Int, accountName: String?, folderPath: String?, recursive: Bool?, databasePath: String?, notesContainerPath: String?, parserMode: String?, parserScriptPath: String?, rubyPath: String?, parserOutputDirectoryPath: String?, outputDirectoryPath: String?, stateDatabasePath: String?)
    case uninstallLaunchAgent(label: String, launchAgentsDirectoryPath: String?)
    case launchAgentStatus(label: String, launchAgentsDirectoryPath: String?)

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
        case "snapshot":
            let options = try parseSnapshotOptions(Array(arguments.dropFirst()))
            return .snapshot(notesContainerPath: options.notesContainerPath, workDirectoryPath: options.workDirectoryPath)
        case "parse":
            let options = try parseParserOptions(Array(arguments.dropFirst()))
            return .parse(
                noteUUID: options.noteUUID,
                databasePath: options.databasePath,
                notesContainerPath: options.notesContainerPath,
                parserMode: options.parserMode,
                parserScriptPath: options.parserScriptPath,
                rubyPath: options.rubyPath,
                outputDirectoryPath: options.outputDirectoryPath,
                debugHTMLDirectoryPath: options.debugHTMLDirectoryPath
            )
        case "export":
            let options = try parseExportOptions(Array(arguments.dropFirst()))
            guard let noteUUID = options.noteUUID else {
                throw CLIError.usage("Missing required option: --note-uuid")
            }
            return .export(
                noteUUID: noteUUID,
                title: options.title,
                htmlPath: options.htmlPath,
                accountName: options.accountName,
                folderPath: options.folderPath,
                notesContainerPath: options.notesContainerPath,
                parserScriptPath: options.parserScriptPath,
                rubyPath: options.rubyPath,
                parserOutputDirectoryPath: options.parserOutputDirectoryPath,
                outputDirectoryPath: options.outputDirectoryPath,
                writeDebugHTML: options.writeDebugHTML
            )
        case "sync":
            let options = try parseSyncOptions(Array(arguments.dropFirst()))
            if options.once, options.watch {
                throw CLIError.usage("Use only one of --once or --watch")
            }
            if options.watch {
                return .syncWatch(
                    dryRun: options.dryRun,
                    accountName: options.accountName,
                    folderPath: options.folderPath,
                    recursive: options.recursive,
                    databasePath: options.databasePath,
                    notesContainerPath: options.notesContainerPath,
                    parserMode: options.parserMode,
                    parserScriptPath: options.parserScriptPath,
                    rubyPath: options.rubyPath,
                    parserOutputDirectoryPath: options.parserOutputDirectoryPath,
                    outputDirectoryPath: options.outputDirectoryPath,
                    stateDatabasePath: options.stateDatabasePath,
                    intervalSeconds: options.intervalSeconds ?? AppConfig.defaultConfig.polling.intervalSeconds,
                    maxRuns: options.maxRuns
                )
            } else if options.once {
                return .syncOnce(
                    dryRun: options.dryRun,
                    accountName: options.accountName,
                    folderPath: options.folderPath,
                    recursive: options.recursive,
                    databasePath: options.databasePath,
                    notesContainerPath: options.notesContainerPath,
                    parserMode: options.parserMode,
                    parserScriptPath: options.parserScriptPath,
                    rubyPath: options.rubyPath,
                    parserOutputDirectoryPath: options.parserOutputDirectoryPath,
                    outputDirectoryPath: options.outputDirectoryPath,
                    stateDatabasePath: options.stateDatabasePath
                )
            }
            throw CLIError.usage("Missing required option: --once or --watch")
        case "install-launch-agent":
            let options = try parseLaunchAgentInstallOptions(Array(arguments.dropFirst()))
            return .installLaunchAgent(
                label: options.label,
                binaryPath: options.binaryPath,
                launchAgentsDirectoryPath: options.launchAgentsDirectoryPath,
                logDirectoryPath: options.logDirectoryPath,
                intervalSeconds: options.intervalSeconds,
                accountName: options.accountName,
                folderPath: options.folderPath,
                recursive: options.recursive,
                databasePath: options.databasePath,
                notesContainerPath: options.notesContainerPath,
                parserMode: options.parserMode,
                parserScriptPath: options.parserScriptPath,
                rubyPath: options.rubyPath,
                parserOutputDirectoryPath: options.parserOutputDirectoryPath,
                outputDirectoryPath: options.outputDirectoryPath,
                stateDatabasePath: options.stateDatabasePath
            )
        case "uninstall-launch-agent":
            let options = try parseLaunchAgentBasicOptions(Array(arguments.dropFirst()))
            return .uninstallLaunchAgent(
                label: options.label,
                launchAgentsDirectoryPath: options.launchAgentsDirectoryPath
            )
        case "launch-agent-status":
            let options = try parseLaunchAgentBasicOptions(Array(arguments.dropFirst()))
            return .launchAgentStatus(
                label: options.label,
                launchAgentsDirectoryPath: options.launchAgentsDirectoryPath
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

    private static func parseSnapshotOptions(_ arguments: [String]) throws -> SnapshotOptions {
        var options = SnapshotOptions()
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--notes-container":
                options.notesContainerPath = try requireValue(iterator.next(), for: argument)
            case "--work-dir":
                options.workDirectoryPath = try requireValue(iterator.next(), for: argument)
            case "--help", "-h":
                throw CLIError.usage(AppRunner.helpText)
            default:
                throw CLIError.usage("Unknown option: \(argument)")
            }
        }

        return options
    }

    private static func parseParserOptions(_ arguments: [String]) throws -> ParserOptions {
        var options = ParserOptions()
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--note-uuid":
                options.noteUUID = try requireValue(iterator.next(), for: argument)
            case "--database":
                options.databasePath = try requireValue(iterator.next(), for: argument)
            case "--notes-container":
                options.notesContainerPath = try requireValue(iterator.next(), for: argument)
            case "--parser-mode":
                options.parserMode = try requireParserMode(iterator.next(), for: argument)
            case "--parser-script":
                options.parserScriptPath = try requireValue(iterator.next(), for: argument)
            case "--ruby":
                options.rubyPath = try requireValue(iterator.next(), for: argument)
            case "--output-dir":
                options.outputDirectoryPath = try requireValue(iterator.next(), for: argument)
            case "--debug-html-dir":
                options.debugHTMLDirectoryPath = try requireValue(iterator.next(), for: argument)
            case "--help", "-h":
                throw CLIError.usage(AppRunner.helpText)
            default:
                throw CLIError.usage("Unknown option: \(argument)")
            }
        }

        return options
    }

    private static func parseExportOptions(_ arguments: [String]) throws -> ExportOptions {
        var options = ExportOptions()
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--note-uuid":
                options.noteUUID = try requireValue(iterator.next(), for: argument)
            case "--title":
                options.title = try requireValue(iterator.next(), for: argument)
            case "--html":
                options.htmlPath = try requireValue(iterator.next(), for: argument)
            case "--account":
                options.accountName = try requireValue(iterator.next(), for: argument)
            case "--folder":
                options.folderPath = try requireValue(iterator.next(), for: argument)
            case "--notes-container":
                options.notesContainerPath = try requireValue(iterator.next(), for: argument)
            case "--parser-mode":
                options.parserMode = try requireParserMode(iterator.next(), for: argument)
            case "--parser-script":
                options.parserScriptPath = try requireValue(iterator.next(), for: argument)
            case "--ruby":
                options.rubyPath = try requireValue(iterator.next(), for: argument)
            case "--parser-output-dir":
                options.parserOutputDirectoryPath = try requireValue(iterator.next(), for: argument)
            case "--output-dir":
                options.outputDirectoryPath = try requireValue(iterator.next(), for: argument)
            case "--debug-html":
                options.writeDebugHTML = true
            case "--help", "-h":
                throw CLIError.usage(AppRunner.helpText)
            default:
                throw CLIError.usage("Unknown option: \(argument)")
            }
        }

        return options
    }

    private static func parseSyncOptions(_ arguments: [String]) throws -> SyncOptions {
        var options = SyncOptions()
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--once":
                options.once = true
            case "--watch":
                options.watch = true
            case "--dry-run":
                options.dryRun = true
            case "--account":
                options.accountName = try requireValue(iterator.next(), for: argument)
            case "--folder":
                options.folderPath = try requireValue(iterator.next(), for: argument)
            case "--recursive":
                options.recursive = true
            case "--database":
                options.databasePath = try requireValue(iterator.next(), for: argument)
            case "--notes-container":
                options.notesContainerPath = try requireValue(iterator.next(), for: argument)
            case "--parser-mode":
                options.parserMode = try requireParserMode(iterator.next(), for: argument)
            case "--parser-script":
                options.parserScriptPath = try requireValue(iterator.next(), for: argument)
            case "--ruby":
                options.rubyPath = try requireValue(iterator.next(), for: argument)
            case "--parser-output-dir":
                options.parserOutputDirectoryPath = try requireValue(iterator.next(), for: argument)
            case "--output-dir":
                options.outputDirectoryPath = try requireValue(iterator.next(), for: argument)
            case "--state-db":
                options.stateDatabasePath = try requireValue(iterator.next(), for: argument)
            case "--interval-seconds":
                options.intervalSeconds = try requirePositiveInt(iterator.next(), for: argument)
            case "--max-runs":
                options.maxRuns = try requireNonNegativeInt(iterator.next(), for: argument)
            case "--help", "-h":
                throw CLIError.usage(AppRunner.helpText)
            default:
                throw CLIError.usage("Unknown option: \(argument)")
            }
        }

        return options
    }

    private static func parseLaunchAgentInstallOptions(_ arguments: [String]) throws -> LaunchAgentInstallOptions {
        var options = LaunchAgentInstallOptions()
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--label":
                options.label = try requireValue(iterator.next(), for: argument)
            case "--binary":
                options.binaryPath = try requireValue(iterator.next(), for: argument)
            case "--launch-agents-dir":
                options.launchAgentsDirectoryPath = try requireValue(iterator.next(), for: argument)
            case "--log-dir":
                options.logDirectoryPath = try requireValue(iterator.next(), for: argument)
            case "--interval-seconds":
                options.intervalSeconds = try requirePositiveInt(iterator.next(), for: argument)
            case "--account":
                options.accountName = try requireValue(iterator.next(), for: argument)
            case "--folder":
                options.folderPath = try requireValue(iterator.next(), for: argument)
            case "--recursive":
                options.recursive = true
            case "--database":
                options.databasePath = try requireValue(iterator.next(), for: argument)
            case "--notes-container":
                options.notesContainerPath = try requireValue(iterator.next(), for: argument)
            case "--parser-mode":
                options.parserMode = try requireParserMode(iterator.next(), for: argument)
            case "--parser-script":
                options.parserScriptPath = try requireValue(iterator.next(), for: argument)
            case "--ruby":
                options.rubyPath = try requireValue(iterator.next(), for: argument)
            case "--parser-output-dir":
                options.parserOutputDirectoryPath = try requireValue(iterator.next(), for: argument)
            case "--output-dir":
                options.outputDirectoryPath = try requireValue(iterator.next(), for: argument)
            case "--state-db":
                options.stateDatabasePath = try requireValue(iterator.next(), for: argument)
            case "--help", "-h":
                throw CLIError.usage(AppRunner.helpText)
            default:
                throw CLIError.usage("Unknown install-launch-agent option: \(argument)")
            }
        }

        return options
    }

    private static func parseLaunchAgentBasicOptions(_ arguments: [String]) throws -> LaunchAgentBasicOptions {
        var options = LaunchAgentBasicOptions()
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--label":
                options.label = try requireValue(iterator.next(), for: argument)
            case "--launch-agents-dir":
                options.launchAgentsDirectoryPath = try requireValue(iterator.next(), for: argument)
            case "--help", "-h":
                throw CLIError.usage(AppRunner.helpText)
            default:
                throw CLIError.usage("Unknown LaunchAgent option: \(argument)")
            }
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

    private static func requireParserMode(_ value: String?, for argument: String) throws -> String {
        let value = try requireValue(value, for: argument)
        guard ["apple-cloud-notes-parser", "native-swift"].contains(value) else {
            throw CLIError.usage("Value for \(argument) must be apple-cloud-notes-parser or native-swift")
        }
        return value
    }

    private static func requirePositiveInt(_ value: String?, for argument: String) throws -> Int {
        let parsed = try requireNonNegativeInt(value, for: argument)
        guard parsed > 0 else {
            throw CLIError.usage("Value for \(argument) must be greater than zero")
        }
        return parsed
    }

    private static func requireNonNegativeInt(_ value: String?, for argument: String) throws -> Int {
        let raw = try requireValue(value, for: argument)
        guard let parsed = Int(raw), parsed >= 0 else {
            throw CLIError.usage("Value for \(argument) must be a non-negative integer")
        }
        return parsed
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

private struct SnapshotOptions {
    var notesContainerPath: String?
    var workDirectoryPath: String?
}

private struct ParserOptions {
    var noteUUID: String?
    var databasePath: String?
    var notesContainerPath: String?
    var parserMode: String?
    var parserScriptPath: String?
    var rubyPath: String?
    var outputDirectoryPath: String?
    var debugHTMLDirectoryPath: String?
}

private struct ExportOptions {
    var noteUUID: String?
    var title: String?
    var htmlPath: String?
    var accountName: String?
    var folderPath: String?
    var notesContainerPath: String?
    var parserMode: String?
    var parserScriptPath: String?
    var rubyPath: String?
    var parserOutputDirectoryPath: String?
    var outputDirectoryPath: String?
    var writeDebugHTML = false
}

private struct SyncOptions {
    var once = false
    var watch = false
    var dryRun = false
    var accountName: String?
    var folderPath: String?
    var recursive: Bool?
    var databasePath: String?
    var notesContainerPath: String?
    var parserMode: String?
    var parserScriptPath: String?
    var rubyPath: String?
    var parserOutputDirectoryPath: String?
    var outputDirectoryPath: String?
    var stateDatabasePath: String?
    var intervalSeconds: Int?
    var maxRuns: Int?
}

private struct LaunchAgentInstallOptions {
    var label = LaunchAgentDefaults.label
    var binaryPath: String?
    var launchAgentsDirectoryPath: String?
    var logDirectoryPath: String?
    var intervalSeconds = AppConfig.defaultConfig.polling.intervalSeconds
    var accountName: String?
    var folderPath: String?
    var recursive: Bool?
    var databasePath: String?
    var notesContainerPath: String?
    var parserMode: String?
    var parserScriptPath: String?
    var rubyPath: String?
    var parserOutputDirectoryPath: String?
    var outputDirectoryPath: String?
    var stateDatabasePath: String?
}

private struct LaunchAgentBasicOptions {
    var label = LaunchAgentDefaults.label
    var launchAgentsDirectoryPath: String?
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
