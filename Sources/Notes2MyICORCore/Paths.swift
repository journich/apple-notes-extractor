import Foundation

public struct AppPaths {
    public let fileManager: FileManager
    public let environment: [String: String]

    public init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.environment = environment
    }

    public var homeDirectory: URL {
        if let home = environment["HOME"], home.isEmpty == false {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser
    }

    public var applicationSupportDirectory: URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Notes2MyICOR", isDirectory: true)
    }

    public var defaultConfigPath: String {
        "~/Library/Application Support/Notes2MyICOR/config.json"
    }

    public func expandPath(_ path: String) -> URL {
        if path == "~" {
            return homeDirectory
        }

        if path.hasPrefix("~/") {
            let suffix = String(path.dropFirst(2))
            return homeDirectory.appendingPathComponent(suffix)
        }

        return URL(fileURLWithPath: path)
    }

    public func createApplicationSupportDirectory() throws -> URL {
        try fileManager.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
        return applicationSupportDirectory
    }
}
