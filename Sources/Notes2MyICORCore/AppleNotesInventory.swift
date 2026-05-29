import Foundation

public struct AppleNotesInventory: Equatable, Sendable {
    public var accounts: [AppleNotesAccount]
    public var folders: [AppleNotesFolder]
    public var notes: [AppleNotesNoteMetadata]

    public init(
        accounts: [AppleNotesAccount],
        folders: [AppleNotesFolder],
        notes: [AppleNotesNoteMetadata]
    ) {
        self.accounts = accounts
        self.folders = folders
        self.notes = notes
    }
}

public struct AppleNotesAccount: Equatable, Sendable {
    public var objectID: Int
    public var uuid: String
    public var name: String

    public init(objectID: Int, uuid: String, name: String) {
        self.objectID = objectID
        self.uuid = uuid
        self.name = name
    }
}

public struct AppleNotesFolder: Equatable, Sendable {
    public var objectID: Int
    public var uuid: String
    public var name: String
    public var accountObjectID: Int?
    public var parentObjectID: Int?

    public init(
        objectID: Int,
        uuid: String,
        name: String,
        accountObjectID: Int?,
        parentObjectID: Int?
    ) {
        self.objectID = objectID
        self.uuid = uuid
        self.name = name
        self.accountObjectID = accountObjectID
        self.parentObjectID = parentObjectID
    }
}

public struct AppleNotesNoteMetadata: Equatable, Sendable {
    public var objectID: Int
    public var uuid: String
    public var title: String
    public var snippet: String?
    public var createdCoreData: Double?
    public var modifiedCoreData: Double?
    public var createdAt: Date?
    public var modifiedAt: Date?
    public var accountObjectID: Int?
    public var folderObjectID: Int?
    public var noteDataObjectID: Int?

    public init(
        objectID: Int,
        uuid: String,
        title: String,
        snippet: String?,
        createdCoreData: Double?,
        modifiedCoreData: Double?,
        createdAt: Date?,
        modifiedAt: Date?,
        accountObjectID: Int?,
        folderObjectID: Int?,
        noteDataObjectID: Int?
    ) {
        self.objectID = objectID
        self.uuid = uuid
        self.title = title
        self.snippet = snippet
        self.createdCoreData = createdCoreData
        self.modifiedCoreData = modifiedCoreData
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.accountObjectID = accountObjectID
        self.folderObjectID = folderObjectID
        self.noteDataObjectID = noteDataObjectID
    }
}

public enum CoreDataTimestamp {
    public static let unixEpochOffset: Double = 978_307_200

    public static func date(fromCoreDataTimestamp timestamp: Double?) -> Date? {
        guard let timestamp else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp + unixEpochOffset)
    }
}
