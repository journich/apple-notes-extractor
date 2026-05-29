import Foundation

public struct AppleNotesInventoryFormatter {
    private let dateFormatter: ISO8601DateFormatter

    public init() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        self.dateFormatter = formatter
    }

    public func formatAccounts(_ accounts: [AppleNotesAccount]) -> String {
        var lines = ["Accounts:"]
        for account in accounts {
            lines.append("- \(account.name) [id=\(account.objectID), uuid=\(account.uuid)]")
        }
        return lines.joined(separator: "\n")
    }

    public func formatFolders(_ folders: [AppleNotesFolder], accounts: [AppleNotesAccount], accountName: String?) throws -> String {
        let selectedAccount = try selectedAccount(named: accountName, accounts: accounts)
        let filteredFolders = selectedAccount.map { account in
            folders.filter { $0.accountObjectID == account.objectID }
        } ?? folders

        let paths = FolderPathBuilder(folders: filteredFolders).pathsByFolderID()
        var lines = ["Folders:"]

        for folder in filteredFolders.sorted(by: { (paths[$0.objectID] ?? $0.name) < (paths[$1.objectID] ?? $1.name) }) {
            let path = paths[folder.objectID] ?? folder.name
            lines.append("- \(path) [id=\(folder.objectID), uuid=\(folder.uuid)]")
        }

        return lines.joined(separator: "\n")
    }

    public func formatNotes(
        _ notes: [AppleNotesNoteMetadata],
        folders: [AppleNotesFolder],
        accounts: [AppleNotesAccount],
        accountName: String?,
        folderPath: String?,
        recursive: Bool
    ) throws -> String {
        let selectedAccount = try selectedAccount(named: accountName, accounts: accounts)
        let accountFolders = selectedAccount.map { account in
            folders.filter { $0.accountObjectID == account.objectID }
        } ?? folders

        let folderPaths = FolderPathBuilder(folders: accountFolders).pathsByFolderID()
        let allowedFolderIDs = try allowedFolders(
            folderPath: folderPath,
            recursive: recursive,
            folders: accountFolders,
            folderPaths: folderPaths
        )

        let filteredNotes = notes.filter { note in
            if let selectedAccount, note.accountObjectID != selectedAccount.objectID {
                return false
            }

            if let allowedFolderIDs {
                guard let folderObjectID = note.folderObjectID else {
                    return false
                }
                return allowedFolderIDs.contains(folderObjectID)
            }

            return true
        }

        var lines = ["Notes:"]
        for note in filteredNotes {
            let folder = note.folderObjectID.flatMap { folderPaths[$0] } ?? ""
            let modified = note.modifiedAt.map { dateFormatter.string(from: $0) } ?? ""
            lines.append("- \(note.title) [uuid=\(note.uuid), folder=\(folder), modified=\(modified)]")
        }

        return lines.joined(separator: "\n")
    }

    private func selectedAccount(named accountName: String?, accounts: [AppleNotesAccount]) throws -> AppleNotesAccount? {
        guard let accountName else {
            return nil
        }

        guard let account = accounts.first(where: { $0.name.caseInsensitiveCompare(accountName) == .orderedSame }) else {
            throw AppleNotesInventoryError.accountNotFound(accountName)
        }

        return account
    }

    private func allowedFolders(
        folderPath: String?,
        recursive: Bool,
        folders: [AppleNotesFolder],
        folderPaths: [Int: String]
    ) throws -> Set<Int>? {
        guard let folderPath else {
            return nil
        }

        guard let root = folders.first(where: { folderPaths[$0.objectID] == folderPath }) else {
            throw AppleNotesInventoryError.folderNotFound(folderPath)
        }

        if recursive == false {
            return [root.objectID]
        }

        let parentMap = Dictionary(grouping: folders, by: { $0.parentObjectID })
        var result: Set<Int> = [root.objectID]
        var stack = [root.objectID]

        while let current = stack.popLast() {
            for child in parentMap[current] ?? [] {
                if result.insert(child.objectID).inserted {
                    stack.append(child.objectID)
                }
            }
        }

        return result
    }
}

public struct FolderPathBuilder {
    public let folders: [AppleNotesFolder]

    public init(folders: [AppleNotesFolder]) {
        self.folders = folders
    }

    public func pathsByFolderID() -> [Int: String] {
        let byID = Dictionary(uniqueKeysWithValues: folders.map { ($0.objectID, $0) })
        var cache: [Int: String] = [:]

        func path(for folder: AppleNotesFolder, visited: Set<Int>) -> String {
            if let cached = cache[folder.objectID] {
                return cached
            }

            guard let parentID = folder.parentObjectID,
                  visited.contains(parentID) == false,
                  let parent = byID[parentID] else {
                cache[folder.objectID] = folder.name
                return folder.name
            }

            let parentPath = path(for: parent, visited: visited.union([folder.objectID]))
            let fullPath = parentPath.isEmpty ? folder.name : "\(parentPath)/\(folder.name)"
            cache[folder.objectID] = fullPath
            return fullPath
        }

        for folder in folders {
            _ = path(for: folder, visited: [])
        }

        return cache
    }
}
