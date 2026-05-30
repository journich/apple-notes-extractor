import Foundation

public enum NoteChangeKind: String, Equatable, Sendable {
    case new = "NEW"
    case modified = "MODIFIED"
    case metadataChanged = "METADATA_CHANGED"
    case unchanged = "UNCHANGED"
    case outOfScope = "OUT_OF_SCOPE"
    case recentlyDeleted = "RECENTLY_DELETED"
    case missingPossiblyDeleted = "MISSING_POSSIBLY_DELETED"
    case deletedAfterGrace = "DELETED_AFTER_GRACE"
    case exportFailed = "EXPORT_FAILED"
}

public struct NoteChange: Equatable, Sendable {
    public var noteUUID: String
    public var kind: NoteChangeKind
    public var note: AppleNotesNoteMetadata?
    public var previousState: NoteState?

    public init(noteUUID: String, kind: NoteChangeKind, note: AppleNotesNoteMetadata?, previousState: NoteState?) {
        self.noteUUID = noteUUID
        self.kind = kind
        self.note = note
        self.previousState = previousState
    }
}

public struct ChangeSummary: Equatable, Sendable {
    public var changes: [NoteChange]

    public init(changes: [NoteChange]) {
        self.changes = changes
    }

    public func count(_ kind: NoteChangeKind) -> Int {
        changes.filter { $0.kind == kind }.count
    }
}

public struct ChangeClassifier {
    public init() {}

    public func classify(
        inScopeNotes: [AppleNotesNoteMetadata],
        allCurrentNotes: [AppleNotesNoteMetadata],
        previousStates: [NoteState],
        allowedFolderIDs: Set<Int>,
        folders: [AppleNotesFolder] = [],
        missingGraceCount: Int
    ) -> ChangeSummary {
        let previousByUUID = Dictionary(uniqueKeysWithValues: previousStates.map { ($0.noteUUID, $0) })
        let inScopeByUUID = Dictionary(uniqueKeysWithValues: inScopeNotes.map { ($0.uuid, $0) })
        let allCurrentByUUID = Dictionary(uniqueKeysWithValues: allCurrentNotes.map { ($0.uuid, $0) })
        let folderPaths = FolderPathBuilder(folders: folders).pathsByFolderID()

        var changes: [NoteChange] = []

        for note in inScopeNotes {
            guard let previous = previousByUUID[note.uuid] else {
                changes.append(NoteChange(noteUUID: note.uuid, kind: .new, note: note, previousState: nil))
                continue
            }

            if previous.exportStatus == "failed" {
                changes.append(NoteChange(noteUUID: note.uuid, kind: .exportFailed, note: note, previousState: previous))
            } else if previous.modifiedCoreData != note.modifiedCoreData {
                changes.append(NoteChange(noteUUID: note.uuid, kind: .modified, note: note, previousState: previous))
            } else if previous.title != note.title || previous.folderPath != note.folderObjectID.map(String.init) {
                changes.append(NoteChange(noteUUID: note.uuid, kind: .metadataChanged, note: note, previousState: previous))
            } else {
                changes.append(NoteChange(noteUUID: note.uuid, kind: .unchanged, note: note, previousState: previous))
            }
        }

        for previous in previousStates where inScopeByUUID[previous.noteUUID] == nil {
            if let current = allCurrentByUUID[previous.noteUUID] {
                if let folderID = current.folderObjectID, allowedFolderIDs.contains(folderID) == false {
                    let kind: NoteChangeKind = isRecentlyDeleted(folderID: folderID, folderPaths: folderPaths)
                        ? .recentlyDeleted
                        : .outOfScope
                    changes.append(NoteChange(noteUUID: previous.noteUUID, kind: kind, note: current, previousState: previous))
                }
            } else {
                let missingCount = previous.missingScanCount + 1
                let kind: NoteChangeKind = missingCount >= missingGraceCount ? .deletedAfterGrace : .missingPossiblyDeleted
                changes.append(NoteChange(noteUUID: previous.noteUUID, kind: kind, note: nil, previousState: previous))
            }
        }

        return ChangeSummary(changes: changes.sorted { $0.noteUUID < $1.noteUUID })
    }

    private func isRecentlyDeleted(folderID: Int, folderPaths: [Int: String]) -> Bool {
        guard let folderPath = folderPaths[folderID] else {
            return false
        }
        return folderPath
            .split(separator: "/")
            .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Recently Deleted") == .orderedSame }
    }
}

public struct ScanSummaryFormatter {
    public init() {}

    public func format(_ summary: ChangeSummary) -> String {
        """
        Scan summary:
        NEW: \(summary.count(.new))
        MODIFIED: \(summary.count(.modified))
        METADATA_CHANGED: \(summary.count(.metadataChanged))
        UNCHANGED: \(summary.count(.unchanged))
        OUT_OF_SCOPE: \(summary.count(.outOfScope))
        RECENTLY_DELETED: \(summary.count(.recentlyDeleted))
        MISSING_POSSIBLY_DELETED: \(summary.count(.missingPossiblyDeleted))
        DELETED_AFTER_GRACE: \(summary.count(.deletedAfterGrace))
        EXPORT_FAILED: \(summary.count(.exportFailed))
        """
    }
}
