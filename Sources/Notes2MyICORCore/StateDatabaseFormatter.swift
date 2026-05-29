import Foundation

public struct StateDatabaseFormatter {
    public init() {}

    public func formatStatus(_ status: StateDatabaseStatus, path: String) -> String {
        """
        State database:
        Path: \(path)
        Schema version: \(status.schemaVersion)
        Notes tracked: \(status.notesCount)
        Scan runs: \(status.scanRunsCount)
        Sync roots: \(status.syncRootsCount)
        """
    }
}
