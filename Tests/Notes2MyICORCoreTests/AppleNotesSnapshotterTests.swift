import Foundation
import XCTest
@testable import Notes2MyICORCore

final class AppleNotesSnapshotterTests: XCTestCase {
    func testSnapshotCopiesExpectedSQLiteFilesAndAssetFolders() throws {
        let directory = try TemporaryDirectory()
        let source = directory.url.appendingPathComponent("group.com.apple.notes", isDirectory: true)
        let work = directory.url.appendingPathComponent("work", isDirectory: true)
        try createFixtureContainer(at: source, includeWAL: true, includeAssets: true)

        let snapshot = try AppleNotesSnapshotter(idGenerator: { "fixed" }).createSnapshot(
            sourceContainer: source,
            workDirectory: work
        )

        XCTAssertEqual(snapshot.snapshotDirectory.lastPathComponent, "snapshot-fixed")
        XCTAssertEqual(snapshot.copiedRelativePaths, [
            "FallbackImages",
            "Media",
            "NoteStore.sqlite",
            "NoteStore.sqlite-shm",
            "NoteStore.sqlite-wal",
            "Previews",
        ])
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.snapshotDirectory.appendingPathComponent("NoteStore.sqlite").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.snapshotDirectory.appendingPathComponent("Media/asset.txt").path))
    }

    func testSnapshotHandlesMissingWALAndAssetFolders() throws {
        let directory = try TemporaryDirectory()
        let source = directory.url.appendingPathComponent("group.com.apple.notes", isDirectory: true)
        let work = directory.url.appendingPathComponent("work", isDirectory: true)
        try createFixtureContainer(at: source, includeWAL: false, includeAssets: false)

        let snapshot = try AppleNotesSnapshotter(idGenerator: { "fixed" }).createSnapshot(
            sourceContainer: source,
            workDirectory: work
        )

        XCTAssertEqual(snapshot.copiedRelativePaths, ["NoteStore.sqlite"])
    }

    func testSnapshotRejectsDestinationInsideLiveContainer() throws {
        let directory = try TemporaryDirectory()
        let source = directory.url.appendingPathComponent("group.com.apple.notes", isDirectory: true)
        try createFixtureContainer(at: source, includeWAL: false, includeAssets: false)

        XCTAssertThrowsError(try AppleNotesSnapshotter().createSnapshot(
            sourceContainer: source,
            workDirectory: source.appendingPathComponent("work")
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("must not be inside"))
        }
    }

    func testSnapshotCleanupRemovesOldSnapshotsOnly() throws {
        let directory = try TemporaryDirectory()
        let work = directory.url.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: work.appendingPathComponent("snapshot-old"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: work.appendingPathComponent("snapshot-new"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: work.appendingPathComponent("other"), withIntermediateDirectories: true)

        try AppleNotesSnapshotter().cleanupSnapshots(in: work, keepingLatest: 1)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: work.path)
        XCTAssertEqual(remaining.filter { $0.hasPrefix("snapshot-") }.count, 1)
        XCTAssertTrue(remaining.contains("other"))
    }

    func testSnapshotFormatterIncludesCopiedItems() throws {
        let snapshot = AppleNotesSnapshot(
            sourceContainerPath: "/source",
            snapshotDirectory: URL(fileURLWithPath: "/work/snapshot"),
            copiedRelativePaths: ["NoteStore.sqlite"]
        )

        let formatted = SnapshotFormatter().format(snapshot)

        XCTAssertTrue(formatted.contains("Snapshot created:"))
        XCTAssertTrue(formatted.contains("Copied items: 1"))
        XCTAssertTrue(formatted.contains("NoteStore.sqlite"))
    }

    private func createFixtureContainer(at source: URL, includeWAL: Bool, includeAssets: Bool) throws {
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("sqlite".utf8).write(to: source.appendingPathComponent("NoteStore.sqlite"))

        if includeWAL {
            try Data("wal".utf8).write(to: source.appendingPathComponent("NoteStore.sqlite-wal"))
            try Data("shm".utf8).write(to: source.appendingPathComponent("NoteStore.sqlite-shm"))
        }

        if includeAssets {
            for directoryName in ["Media", "FallbackImages", "Previews"] {
                let directory = source.appendingPathComponent(directoryName, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data("asset".utf8).write(to: directory.appendingPathComponent("asset.txt"))
            }
        }
    }
}
