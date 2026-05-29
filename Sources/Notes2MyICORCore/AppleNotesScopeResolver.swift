import Foundation

public struct AppleNotesScopeRequest: Equatable, Sendable {
    public var accountName: String
    public var folderPath: String
    public var recursive: Bool

    public init(accountName: String, folderPath: String, recursive: Bool) {
        self.accountName = accountName
        self.folderPath = folderPath
        self.recursive = recursive
    }
}

public struct AppleNotesScopeResolution: Equatable, Sendable {
    public var account: AppleNotesAccount
    public var rootFolder: AppleNotesFolder
    public var rootFolderPath: String
    public var allowedFolderIDs: Set<Int>
    public var folderPathsByID: [Int: String]

    public init(
        account: AppleNotesAccount,
        rootFolder: AppleNotesFolder,
        rootFolderPath: String,
        allowedFolderIDs: Set<Int>,
        folderPathsByID: [Int: String]
    ) {
        self.account = account
        self.rootFolder = rootFolder
        self.rootFolderPath = rootFolderPath
        self.allowedFolderIDs = allowedFolderIDs
        self.folderPathsByID = folderPathsByID
    }
}

public enum AppleNotesScopeError: Error, Equatable, LocalizedError {
    case accountNotFound(String)
    case folderPathNotFound(accountName: String, folderPath: String)
    case ambiguousFolderPath(accountName: String, folderPath: String, matches: Int)

    public var errorDescription: String? {
        switch self {
        case .accountNotFound(let accountName):
            "Apple Notes account not found: \(accountName)"
        case .folderPathNotFound(let accountName, let folderPath):
            "Apple Notes folder path not found under \(accountName): \(folderPath)"
        case .ambiguousFolderPath(let accountName, let folderPath, let matches):
            "Apple Notes folder path is ambiguous under \(accountName): \(folderPath) matched \(matches) folders"
        }
    }
}

public struct AppleNotesScopeResolver {
    public init() {}

    public func resolve(_ request: AppleNotesScopeRequest, inventory: AppleNotesInventory) throws -> AppleNotesScopeResolution {
        guard let account = inventory.accounts.first(where: { $0.name.caseInsensitiveCompare(request.accountName) == .orderedSame }) else {
            throw AppleNotesScopeError.accountNotFound(request.accountName)
        }

        let accountFolders = inventory.folders.filter { $0.accountObjectID == account.objectID }
        let paths = FolderPathBuilder(folders: accountFolders).pathsByFolderID()
        let matches = accountFolders.filter { paths[$0.objectID] == request.folderPath }

        guard matches.isEmpty == false else {
            throw AppleNotesScopeError.folderPathNotFound(accountName: account.name, folderPath: request.folderPath)
        }

        guard matches.count == 1, let root = matches.first else {
            throw AppleNotesScopeError.ambiguousFolderPath(
                accountName: account.name,
                folderPath: request.folderPath,
                matches: matches.count
            )
        }

        let allowedFolderIDs: Set<Int>
        if request.recursive {
            allowedFolderIDs = descendantsIncludingSelf(root.objectID, folders: accountFolders)
        } else {
            allowedFolderIDs = [root.objectID]
        }

        return AppleNotesScopeResolution(
            account: account,
            rootFolder: root,
            rootFolderPath: paths[root.objectID] ?? root.name,
            allowedFolderIDs: allowedFolderIDs,
            folderPathsByID: paths
        )
    }

    private func descendantsIncludingSelf(_ rootID: Int, folders: [AppleNotesFolder]) -> Set<Int> {
        let childrenByParent = Dictionary(grouping: folders, by: { $0.parentObjectID })
        var result: Set<Int> = [rootID]
        var stack = [rootID]

        while let current = stack.popLast() {
            for child in childrenByParent[current] ?? [] {
                if result.insert(child.objectID).inserted {
                    stack.append(child.objectID)
                }
            }
        }

        return result
    }
}

public struct ScopeResolutionFormatter {
    public init() {}

    public func format(_ resolution: AppleNotesScopeResolution) -> String {
        var lines: [String] = []
        lines.append("Resolved scope:")
        lines.append("Account: \(resolution.account.name) [id=\(resolution.account.objectID), uuid=\(resolution.account.uuid)]")
        lines.append("Root folder: \(resolution.rootFolderPath) [id=\(resolution.rootFolder.objectID), uuid=\(resolution.rootFolder.uuid)]")
        lines.append("Allowed folders: \(resolution.allowedFolderIDs.count)")

        for folderID in resolution.allowedFolderIDs.sorted() {
            let path = resolution.folderPathsByID[folderID] ?? ""
            lines.append("- \(path) [id=\(folderID)]")
        }

        return lines.joined(separator: "\n")
    }
}
