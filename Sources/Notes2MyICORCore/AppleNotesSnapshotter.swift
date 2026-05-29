import Foundation

public struct AppleNotesSnapshot: Equatable, Sendable {
    public var sourceContainerPath: String
    public var snapshotDirectory: URL
    public var copiedRelativePaths: [String]

    public init(sourceContainerPath: String, snapshotDirectory: URL, copiedRelativePaths: [String]) {
        self.sourceContainerPath = sourceContainerPath
        self.snapshotDirectory = snapshotDirectory
        self.copiedRelativePaths = copiedRelativePaths
    }
}

public enum AppleNotesSnapshotError: Error, Equatable, LocalizedError {
    case sourceContainerNotFound(String)
    case noteStoreNotFound(String)
    case unsafeDestination(String)

    public var errorDescription: String? {
        switch self {
        case .sourceContainerNotFound(let path):
            "Apple Notes container not found: \(path)"
        case .noteStoreNotFound(let path):
            "Apple Notes NoteStore.sqlite not found: \(path)"
        case .unsafeDestination(let path):
            "Snapshot destination must not be inside the live Apple Notes container: \(path)"
        }
    }
}

public struct AppleNotesSnapshotter {
    public let fileManager: FileManager
    public let idGenerator: @Sendable () -> String

    public init(
        fileManager: FileManager = .default,
        idGenerator: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.fileManager = fileManager
        self.idGenerator = idGenerator
    }

    public func createSnapshot(sourceContainer: URL, workDirectory: URL) throws -> AppleNotesSnapshot {
        let source = sourceContainer.standardizedFileURL
        let work = workDirectory.standardizedFileURL
        let sourcePath = source.path

        guard fileManager.fileExists(atPath: sourcePath) else {
            throw AppleNotesSnapshotError.sourceContainerNotFound(sourcePath)
        }

        let noteStoreURL = source.appendingPathComponent("NoteStore.sqlite")
        guard fileManager.fileExists(atPath: noteStoreURL.path) else {
            throw AppleNotesSnapshotError.noteStoreNotFound(noteStoreURL.path)
        }

        if isDescendant(work, of: source) || work.path == source.path {
            throw AppleNotesSnapshotError.unsafeDestination(work.path)
        }

        let snapshotDirectory = work
            .appendingPathComponent("snapshot-\(idGenerator())", isDirectory: true)
            .standardizedFileURL
        try fileManager.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)

        var copied: [String] = []

        for fileName in ["NoteStore.sqlite", "NoteStore.sqlite-wal", "NoteStore.sqlite-shm"] {
            let relativePath = fileName
            let sourceURL = source.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: sourceURL.path) {
                try copyItem(from: sourceURL, to: snapshotDirectory.appendingPathComponent(relativePath))
                copied.append(relativePath)
            }
        }

        for directoryName in ["Media", "FallbackImages", "Previews"] {
            let sourceURL = source.appendingPathComponent(directoryName, isDirectory: true)
            if fileManager.fileExists(atPath: sourceURL.path) {
                try copyItem(from: sourceURL, to: snapshotDirectory.appendingPathComponent(directoryName, isDirectory: true))
                copied.append(directoryName)
            }
        }

        return AppleNotesSnapshot(
            sourceContainerPath: sourcePath,
            snapshotDirectory: snapshotDirectory,
            copiedRelativePaths: copied.sorted()
        )
    }

    public func cleanupSnapshots(in workDirectory: URL, keepingLatest keepCount: Int) throws {
        guard fileManager.fileExists(atPath: workDirectory.path) else {
            return
        }

        let snapshotURLs = try fileManager.contentsOfDirectory(
            at: workDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.lastPathComponent.hasPrefix("snapshot-") }
        .sorted { left, right in
            let leftDate = (try? left.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return leftDate > rightDate
        }

        for oldSnapshot in snapshotURLs.dropFirst(max(keepCount, 0)) {
            try fileManager.removeItem(at: oldSnapshot)
        }
    }

    private func copyItem(from source: URL, to destination: URL) throws {
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func isDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let ancestorPath = ancestor.standardizedFileURL.path
        return candidatePath.hasPrefix(ancestorPath + "/")
    }
}

public struct SnapshotFormatter {
    public init() {}

    public func format(_ snapshot: AppleNotesSnapshot) -> String {
        var lines: [String] = []
        lines.append("Snapshot created:")
        lines.append("Directory: \(snapshot.snapshotDirectory.path)")
        lines.append("Copied items: \(snapshot.copiedRelativePaths.count)")
        for path in snapshot.copiedRelativePaths {
            lines.append("- \(path)")
        }
        return lines.joined(separator: "\n")
    }
}
