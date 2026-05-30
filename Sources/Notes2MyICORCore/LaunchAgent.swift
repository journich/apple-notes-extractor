import Foundation

public struct LaunchAgentConfig: Equatable, Sendable {
    public var label: String
    public var executableURL: URL
    public var syncArguments: [String]
    public var intervalSeconds: Int
    public var standardOutURL: URL
    public var standardErrorURL: URL
    public var runAtLoad: Bool

    public init(
        label: String = LaunchAgentDefaults.label,
        executableURL: URL,
        syncArguments: [String],
        intervalSeconds: Int = AppConfig.defaultConfig.polling.intervalSeconds,
        standardOutURL: URL,
        standardErrorURL: URL,
        runAtLoad: Bool = false
    ) {
        self.label = label
        self.executableURL = executableURL
        self.syncArguments = syncArguments
        self.intervalSeconds = intervalSeconds
        self.standardOutURL = standardOutURL
        self.standardErrorURL = standardErrorURL
        self.runAtLoad = runAtLoad
    }
}

public enum LaunchAgentDefaults {
    public static let label = "com.journich.notes2myicor"
    public static let standardOutFileName = "notes2myicor.out.log"
    public static let standardErrorFileName = "notes2myicor.err.log"
}

public enum LaunchAgentError: Error, Equatable, LocalizedError {
    case invalidLabel(String)
    case invalidInterval(Int)
    case unsafeBinaryPath(String)

    public var errorDescription: String? {
        switch self {
        case .invalidLabel(let label):
            "Invalid LaunchAgent label: \(label)"
        case .invalidInterval(let interval):
            "LaunchAgent interval must be greater than zero: \(interval)"
        case .unsafeBinaryPath(let path):
            "Unsafe LaunchAgent binary path: \(path)"
        }
    }
}

public struct LaunchAgentPlistGenerator {
    public init() {}

    public func plistData(for config: LaunchAgentConfig) throws -> Data {
        try validate(config)

        let plist: [String: Any] = [
            "Label": config.label,
            "ProgramArguments": [config.executableURL.path] + config.syncArguments,
            "RunAtLoad": config.runAtLoad,
            "StandardErrorPath": config.standardErrorURL.path,
            "StandardOutPath": config.standardOutURL.path,
            "StartInterval": config.intervalSeconds,
        ]

        return try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
    }

    public func validate(_ config: LaunchAgentConfig) throws {
        guard config.label.isEmpty == false,
              config.label.contains("/") == false,
              config.label.contains(":") == false else {
            throw LaunchAgentError.invalidLabel(config.label)
        }

        guard config.intervalSeconds > 0 else {
            throw LaunchAgentError.invalidInterval(config.intervalSeconds)
        }
    }
}

public struct LaunchAgentStatus: Equatable, Sendable {
    public var label: String
    public var plistURL: URL
    public var isInstalled: Bool

    public init(label: String, plistURL: URL, isInstalled: Bool) {
        self.label = label
        self.plistURL = plistURL
        self.isInstalled = isInstalled
    }
}

public struct LaunchAgentManager {
    public let fileManager: FileManager
    public let generator: LaunchAgentPlistGenerator

    public init(
        fileManager: FileManager = .default,
        generator: LaunchAgentPlistGenerator = LaunchAgentPlistGenerator()
    ) {
        self.fileManager = fileManager
        self.generator = generator
    }

    @discardableResult
    public func install(_ config: LaunchAgentConfig, launchAgentsDirectory: URL) throws -> URL {
        try validateExecutable(config.executableURL)
        let data = try generator.plistData(for: config)
        let url = try plistURL(label: config.label, launchAgentsDirectory: launchAgentsDirectory)
        try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
        return url
    }

    @discardableResult
    public func uninstall(label: String, launchAgentsDirectory: URL) throws -> URL {
        let url = try plistURL(label: label, launchAgentsDirectory: launchAgentsDirectory)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        return url
    }

    public func status(label: String, launchAgentsDirectory: URL) throws -> LaunchAgentStatus {
        let url = try plistURL(label: label, launchAgentsDirectory: launchAgentsDirectory)
        return LaunchAgentStatus(
            label: label,
            plistURL: url,
            isInstalled: fileManager.fileExists(atPath: url.path)
        )
    }

    public func plistURL(label: String, launchAgentsDirectory: URL) throws -> URL {
        guard label.isEmpty == false,
              label.contains("/") == false,
              label.contains(":") == false else {
            throw LaunchAgentError.invalidLabel(label)
        }
        return launchAgentsDirectory.appendingPathComponent("\(label).plist")
    }

    private func validateExecutable(_ url: URL) throws {
        guard url.isFileURL, url.path.hasPrefix("/") else {
            throw LaunchAgentError.unsafeBinaryPath(url.path)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue == false,
              fileManager.isExecutableFile(atPath: url.path) else {
            throw LaunchAgentError.unsafeBinaryPath(url.path)
        }
    }
}

public struct LaunchAgentFormatter {
    public init() {}

    public func formatInstalled(plistURL: URL) -> String {
        """
        LaunchAgent installed:
        PLIST: \(plistURL.path)
        Load status: will run at login or after launchd loads the plist.
        """
    }

    public func formatUninstalled(plistURL: URL) -> String {
        """
        LaunchAgent uninstalled:
        PLIST: \(plistURL.path)
        """
    }

    public func formatStatus(_ status: LaunchAgentStatus) -> String {
        """
        LaunchAgent status:
        LABEL: \(status.label)
        PLIST: \(status.plistURL.path)
        INSTALLED: \(status.isInstalled ? "true" : "false")
        """
    }
}
