import Foundation

public struct AppleNotesPaths {
    public let paths: AppPaths

    public init(paths: AppPaths = AppPaths()) {
        self.paths = paths
    }

    public var groupContainerURL: URL {
        paths.expandPath(AppConfig.defaultConfig.paths.notesGroupContainer).standardizedFileURL
    }

    public var noteStoreDatabaseURL: URL {
        groupContainerURL.appendingPathComponent("NoteStore.sqlite").standardizedFileURL
    }
}
