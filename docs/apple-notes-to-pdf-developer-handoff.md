# Apple Notes to PDF Sync Utility: Developer Handoff Specification

**Prepared for:** Project owner  
**Date:** 2026-05-29  
**Working project name:** `Notes2MyICOR` / `AppleNotesPDFSync`  
**Primary objective:** Automatically convert Apple Notes created or edited on an iPad into PDF files on a Mac, written to a designated folder for ingestion by myICOR or any similar folder-based knowledge system.

---

## 1. Executive Summary

The desired application is a macOS utility that monitors Apple Notes data already synced locally to the Mac via iCloud, detects new and modified notes under a selected Apple Notes folder tree, reconstructs each changed note, renders it to PDF, and writes the resulting PDF to a designated output folder.

The user does **not** want a manual workflow such as:

```text
Open Apple Note → Share → Export → Save PDF manually
```

The user also does **not** want to rely on PDF Expert or another PDF-native iPad app. The desired capture experience is:

```text
iPad Apple Notes
  → user writes/sketches/diagrams naturally
  → iCloud syncs to Mac
  → Mac utility detects changed note
  → utility exports/render note to PDF
  → PDF appears in myICOR input folder
```

The tool should be stateful, safe, conservative with deletion, and robust enough for a long-running personal workflow.

### Recommended implementation language

**Recommendation: Swift for v1.**

Rust is technically feasible, especially for a CLI parser, but Swift is a better first choice because this project is macOS-specific and benefits from Apple-native frameworks:

- `Foundation` for filesystem, dates, processes and timers.
- `SQLite3` directly, or `GRDB.swift`, for local state DB and Apple Notes metadata reads.
- `SwiftProtobuf` for Apple Notes protobuf decoding if reimplementing parser logic.
- `Compression` or zlib for gzipped note payloads.
- `WebKit` / `WKWebView.createPDF` for HTML-to-PDF rendering.
- `PDFKit` for PDF merging, page handling, metadata, and writing.
- `launchd` / LaunchAgent integration for periodic background operation.
- Optional SwiftUI menu bar app or settings UI.

**Recommended development strategy:**

1. Build a Swift sync/export app.
2. Initially call existing Apple Cloud Notes Parser as a reference/extraction engine or test oracle.
3. Gradually replace the parser dependency with native Swift decoding for only the features required by this project.
4. Keep the project open source, but clearly credit Apple Cloud Notes Parser if using its MIT-licensed logic, protobuf definitions, or derived knowledge.

---

## 2. Requirements

### 2.1 Functional requirements

The application should:

1. Run on macOS.
2. Require no iCloud credentials or Apple ID password.
3. Work from the local Apple Notes data already synced by macOS.
4. Allow a configured Apple Notes account, for example `iCloud`.
5. Allow a configured root folder, for example `myICOR Capture`.
6. Optionally include all subfolders under that folder.
7. Detect new notes since the previous scan.
8. Detect modified notes and re-export them.
9. Detect notes moved out of scope.
10. Detect deleted or missing notes conservatively.
11. Render new/modified notes to PDF.
12. Write PDFs to a configured destination folder.
13. Keep a separate local SQLite state database to track exported notes.
14. Never modify the Apple Notes database.
15. Never automatically destroy exported PDFs.
16. Log errors without aborting the whole run when one note fails.
17. Optionally write sidecar JSON metadata next to each PDF.
18. Run manually from CLI and optionally automatically via `launchd`.

### 2.2 Non-functional requirements

The application should be:

- Read-only with respect to Apple Notes data.
- Deterministic enough for repeated sync runs.
- Safe around iCloud sync races and WAL-mode SQLite behavior.
- Transparent about unsupported note features.
- Able to recover from parser/render failures.
- Able to handle thousands of notes without re-exporting everything every run.
- Open-source friendly.

### 2.3 Out of scope for v1

Avoid these in v1:

- iCloud web authentication.
- iCloud API / CloudKit remote calls.
- iTunes/Finder backup parsing.
- Docker packaging.
- Full forensic reporting.
- Locked-note decryption.
- Cross-platform support.
- Pixel-perfect Apple Notes rendering.
- Editing Apple Notes.
- Exporting all possible historical Apple Notes database formats.

---

## 3. Clarified User Intent

The user originally considered using PDF Expert because it saves directly into PDFs, but would prefer not to pay for an expensive PDF editor. The user wants to keep using Apple Notes on iPad because it is natural for handwriting, sketches, and diagrams.

The user does **not** want to remember to import a blank PDF into a note first. The ideal note-creation workflow should simply be:

```text
Open Apple Notes on iPad
Create note in a chosen folder
Handwrite/sketch/diagram
Done
```

The Mac-side application should do the rest.

---

## 4. Key Apple Notes Concepts

### 4.1 Account

In Apple Notes, an **account** is the top-level storage area in the Notes sidebar. It is not necessarily the iCloud email address.

Examples:

```text
iCloud
On My Mac
Gmail
Yahoo
Exchange
```

For this user, the likely target account is:

```text
iCloud
```

The application should therefore expose configuration like:

```toml
account_name = "iCloud"
folder_path = "myICOR Capture"
recursive = true
```

Internally, resolve this account to stable database identifiers if available.

### 4.2 Folder

A folder is a container under an account. Apple Notes supports folders and subfolders.

Example:

```text
Notes
  iCloud
    myICOR Capture
      Sketches
      Diagrams
      Course Ideas
```

The exporter should support folder-scoped sync:

```text
Export only notes in:
  iCloud / myICOR Capture

And, if recursive=true, also:
  iCloud / myICOR Capture / Sketches
  iCloud / myICOR Capture / Diagrams
  iCloud / myICOR Capture / Course Ideas
```

It should ignore all notes outside that folder tree.

### 4.3 Why account + folder path are both required

Filtering only by folder name is dangerous. There may be duplicate folder names under different parents or accounts.

Bad:

```text
folder_name == "Sketches"
```

Better:

```text
account == "iCloud"
folder_path == "myICOR Capture/Sketches"
```

Best internally:

```text
account_uuid + root_folder_uuid + descendant folder UUID set
```

---

## 5. Authentication and Permissions

### 5.1 No iCloud authentication required

The application should not authenticate to iCloud. It should not ask for Apple ID credentials, handle 2FA, use OAuth, or talk to Apple servers.

The intended architecture is:

```text
iPad Apple Notes
  → iCloud sync handled by Apple/macOS
  → Mac local Apple Notes database
  → Notes2MyICOR reads local database and files
  → PDF output folder
```

The user is already logged into iCloud on the Mac, and macOS handles the sync.

### 5.2 Local permission still required

The app will need local filesystem/privacy permission to read the Apple Notes container, usually:

```text
~/Library/Group Containers/group.com.apple.notes/
```

A CLI or LaunchAgent may require the user to grant **Full Disk Access** to the binary, Terminal, or hosting app. A sandboxed App Store-style app may have additional restrictions and may not be able to read this location without user-granted access or special handling.

### 5.3 Important distinction

Apple Notes are not stored as normal user files in iCloud Drive such as:

```text
iCloud Drive/Notes/My Note.note
```

They are stored in a local app data store that syncs through iCloud.

---

## 6. Apple Notes Storage Overview

### 6.1 Main local path

The modern Mac Apple Notes data store is commonly located at:

```text
~/Library/Group Containers/group.com.apple.notes/
```

The main SQLite store is commonly:

```text
~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite
```

Related files may include:

```text
NoteStore.sqlite-wal
NoteStore.sqlite-shm
Media/
FallbackImages/
Previews/
```

Exact folders can vary by macOS version and data state.

### 6.2 Apple Notes is not stored as plain text

Modern Apple Notes data is not simple HTML or Markdown. It is stored across SQLite tables plus compressed protobuf data. Apple Cloud Notes Parser exists because the storage format is non-trivial.

Relevant Apple Cloud Notes Parser statement:

> Apple Notes data is stored in a series of protobufs and tables in the database and it is not always easy to piece them back together by hand.

Source:  
https://github.com/threeplanetssoftware/apple_cloud_notes_parser

### 6.3 Main observed tables

The most important tables for this project are typically:

```text
ZICCLOUDSYNCINGOBJECT
ZICNOTEDATA
```

`ZICCLOUDSYNCINGOBJECT` contains metadata and rows for notes, folders, accounts, and other iCloud-synced objects. `ZICNOTEDATA` is linked to note body data.

Important observed fields include:

```text
ZICCLOUDSYNCINGOBJECT.Z_PK
ZICCLOUDSYNCINGOBJECT.ZIDENTIFIER
ZICCLOUDSYNCINGOBJECT.ZTITLE1
ZICCLOUDSYNCINGOBJECT.ZSNIPPET
ZICCLOUDSYNCINGOBJECT.ZCREATIONDATE1
ZICCLOUDSYNCINGOBJECT.ZMODIFICATIONDATE1
ZICCLOUDSYNCINGOBJECT.ZFOLDER
ZICCLOUDSYNCINGOBJECT.ZNOTEDATA
ZICNOTEDATA.ZDATA
```

**Warning:** Apple’s Notes database schema is private and changes over time. Do not assume all column names are stable forever. Implement schema introspection and good error reporting.

---

## 7. Apple Notes Export Limitation That Motivated This Project

Apple Notes can manually export a note as PDF, but the built-in export path has limitations. Apple’s support documentation says that if a note contains a scanned document or PDF with multiple pages, only the first page of that embedded scanned document/PDF is included when exporting the note to PDF.

Apple Notes export reference:  
https://support.apple.com/guide/iphone/export-or-print-notes-iphdf551cfa2/ios  
https://support.apple.com/guide/ipad/export-or-print-notes-ipad50c393a8/ipados

This project should not rely on manual Apple Notes export. It should reconstruct notes from the local data store and render them independently.

---

## 8. Existing Reference Project: Apple Cloud Notes Parser

### 8.1 What it is

Apple Cloud Notes Parser is an existing open-source project:

```text
threeplanetssoftware/apple_cloud_notes_parser
```

GitHub:  
https://github.com/threeplanetssoftware/apple_cloud_notes_parser

It is authored by Jon Baumann / Three Planets Software / Ciofeca Forensics. It is not an Apple product.

The project describes itself as:

> a parser for the current version of Apple Notes data syncable with iCloud as seen on Apple handsets in iOS 9 and later.

### 8.2 License

The project is MIT licensed.

License file:  
https://github.com/threeplanetssoftware/apple_cloud_notes_parser/blob/master/LICENSE

MIT license permits use, copying, modification, publication and distribution, provided the copyright and permission notice are included in copies or substantial portions of the software.

If this project uses Apple Cloud Notes Parser code, protobuf definitions, field mappings, or substantial derived logic, include a third-party notice.

Suggested notice:

```text
This project uses implementation knowledge, protobuf definitions, or parsing logic derived from Apple Cloud Notes Parser by Three Planets Software, licensed under the MIT License.
Source: https://github.com/threeplanetssoftware/apple_cloud_notes_parser
```

### 8.3 Relevant features

Apple Cloud Notes Parser can:

- Parse iOS 9-26 Cloud Notes files.
- Parse Mac Apple Notes data using the `--mac` option.
- Rebuild notes as HTML.
- Extract embedded images/files from full backups or Mac Notes folders.
- Generate CSV and JSON summaries.
- Output individual HTML files per note.
- Use UUIDs instead of local database IDs.
- Retain Apple Notes display order.

Relevant README sections and options:

```text
--mac DIRECTORY
--one-output-folder
--individual-files
--uuid
--retain-display-order
```

Apple Cloud Notes Parser README:  
https://github.com/threeplanetssoftware/apple_cloud_notes_parser

JSON output documentation:  
https://github.com/threeplanetssoftware/apple_cloud_notes_parser/blob/master/JSON.md

### 8.4 How it reconstructs notes

The README explains that, once `NoteStore.sqlite` is opened, the program creates account/folder/note objects and, for each note, takes the gzipped blob in `ZDATA`, gunzips it, and parses the protobuf inside.

This is the critical reference path for a native Swift or Rust implementation:

```text
ZICNOTEDATA.ZDATA
  → gunzip/decompress
  → protobuf decode
  → note document model
  → HTML
  → PDF
```

### 8.5 Use as reference/test oracle

Even if the final application is Swift, Apple Cloud Notes Parser should be kept as a development reference and regression oracle.

Recommended approach:

1. Create a small corpus of test Apple Notes.
2. Run Apple Cloud Notes Parser on the corpus.
3. Capture its JSON/HTML output.
4. Run the Swift implementation on the same data.
5. Compare metadata, plaintext, HTML, embedded object counts and rendered output.

---

## 9. Recommended Architecture

### 9.1 High-level pipeline

```text
Apple Notes on iPad
  → iCloud sync handled by Apple
  → Mac local Notes database
  → metadata scanner
  → state DB comparison
  → changed note set
  → parser/reconstructor
  → HTML document
  → PDF renderer
  → output folder
  → sidecar JSON
  → state DB update
```

### 9.2 Components

```text
Notes2MyICOR
  App/CLI entrypoint
  Config manager
  Apple Notes metadata reader
  Folder tree resolver
  Sync state database
  Change classifier
  Apple Notes parser/reconstructor
  HTML renderer
  PDF renderer
  PDF merger/attachment handler
  Output writer
  Deletion/out-of-scope handler
  Logger
  LaunchAgent installer/helper
```

### 9.3 Recommended Swift module layout

```text
Sources/
  Notes2MyICORCLI/
    main.swift

  Notes2MyICORCore/
    Config.swift
    Logger.swift
    Paths.swift

    AppleNotes/
      AppleNotesStore.swift
      AppleNotesMetadataReader.swift
      AppleNotesSchemaInspector.swift
      AppleNotesFolderResolver.swift
      AppleNotesModels.swift

    Parsing/
      NoteDataExtractor.swift
      ProtobufDecoder.swift
      EmbeddedObjectExtractor.swift
      NoteDocument.swift

    Rendering/
      HTMLRenderer.swift
      PDFRenderer.swift
      PDFMerger.swift
      SidecarWriter.swift

    Sync/
      SyncEngine.swift
      ChangeClassifier.swift
      StateDatabase.swift
      DeletionPolicy.swift
      OutputNaming.swift

    LaunchAgent/
      LaunchAgentInstaller.swift
```

---

## 10. Technology Recommendation: Swift vs Rust

### 10.1 Swift recommendation

Swift is recommended for v1 because this is a Mac-native application that needs to integrate cleanly with Apple frameworks.

Useful Swift/Apple technologies:

| Need | Swift/Apple option |
|---|---|
| SQLite reads/writes | `SQLite3` C API or `GRDB.swift` |
| Protobuf decode | `SwiftProtobuf` |
| Gzip/zlib | `Compression`, zlib, or third-party Swift package |
| HTML rendering | `WebKit` / `WKWebView` |
| PDF generation from HTML | `WKWebView.createPDF(configuration:)` |
| PDF manipulation | `PDFKit` |
| File access | `Foundation.FileManager` |
| Background scheduling | `launchd` LaunchAgent |
| Optional UI | SwiftUI menu bar app |

References:

- SwiftProtobuf: https://github.com/apple/swift-protobuf
- GRDB.swift: https://github.com/groue/GRDB.swift
- WKWebView `createPDF`: https://developer.apple.com/documentation/webkit/wkwebview/createpdf%28configuration:completionhandler:%29
- PDFKit: https://developer.apple.com/documentation/pdfkit
- PDFDocument: https://developer.apple.com/documentation/pdfkit/pdfdocument
- PDFDocument `write(to:)`: https://developer.apple.com/documentation/pdfkit/pdfdocument/write%28to:withoptions:%29

### 10.2 Rust alternative

Rust is feasible and attractive for:

- CLI-first development.
- Strong correctness and performance.
- `rusqlite` for SQLite.
- `prost` for protobuf.
- `flate2` for gzip.
- `serde` for JSON.
- Good open-source ergonomics.

But Rust has weaker integration with Apple-native PDF/WebKit APIs. A Rust version would likely call an external renderer such as headless Chromium or use macOS APIs through FFI, increasing complexity.

Rust is a good choice if the goal is a cross-platform parser library. Swift is a better choice if the goal is a polished Mac-native tool for one user’s iCloud-synced Apple Notes.

### 10.3 Final recommendation

Build the production utility in **Swift**.

Use Rust only if:

- you strongly prefer a CLI-only app,
- you want cross-platform parser tooling,
- or you want to build a general Apple Notes parser library independent of Apple UI frameworks.

---

## 11. Configuration Design

Use a simple config file, for example:

```toml
[scope]
account_name = "iCloud"
folder_path = "myICOR Capture"
recursive = true
include_recently_deleted = false

[paths]
notes_group_container = "~/Library/Group Containers/group.com.apple.notes"
output_dir = "~/myICOR/Inbox/Apple Notes"
state_db = "~/Library/Application Support/Notes2MyICOR/state.sqlite"
work_dir = "~/Library/Application Support/Notes2MyICOR/work"

[polling]
interval_seconds = 300
full_inventory_every_runs = 12
missing_scan_grace_count = 3

[export]
write_sidecar_json = true
mirror_folder_tree = true
filename_strategy = "uuid-title"
render_format = "A4"
append_embedded_pdfs = true
never_delete_exported_pdfs = true

[parser]
mode = "native-swift"
# or initially: "apple-cloud-notes-parser"
apple_cloud_notes_parser_path = "~/src/apple_cloud_notes_parser/notes_cloud_ripper.rb"
```

---

## 12. Folder Scoping Algorithm

### 12.1 Goal

Export only notes inside a configured root folder and optionally below it.

Example config:

```toml
account_name = "iCloud"
folder_path = "myICOR Capture"
recursive = true
```

### 12.2 Algorithm

```text
1. Load all accounts.
2. Resolve account_name to account object/ID.
3. Load all folders for that account.
4. Build parent-child folder tree.
5. Resolve folder_path to root folder UUID.
6. If recursive=true:
     allowed_folder_ids = root + all descendants
   Else:
     allowed_folder_ids = root only
7. Export only notes whose folder_id is in allowed_folder_ids.
```

### 12.3 Pseudocode

```swift
let accounts = try notesReader.loadAccounts()
let account = try accounts.resolve(name: config.scope.accountName)

let folders = try notesReader.loadFolders(accountID: account.id)
let rootFolder = try folders.resolvePath(config.scope.folderPath)

let allowedFolderIDs: Set<String>
if config.scope.recursive {
    allowedFolderIDs = folders.descendantsIncludingSelf(rootFolder.id)
} else {
    allowedFolderIDs = [rootFolder.id]
}

let notes = try notesReader.loadNotes(accountID: account.id)
let inScopeNotes = notes.filter { allowedFolderIDs.contains($0.folderID) }
```

### 12.4 Moved notes

If a previously exported note is still present in Apple Notes but no longer inside the allowed folder set, mark it `out_of_scope`, not deleted.

```text
note exists + folder outside scope = out of scope
note missing entirely = possible deletion
```

---

## 13. Metadata Reading

### 13.1 Live read-only reads are acceptable for polling

For fast polling, read the live Apple Notes SQLite database in read-only mode.

Use SQLite URI mode:

```text
file:/Users/<user>/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite?mode=ro
```

Also set:

```sql
PRAGMA query_only = ON;
```

SQLite references:

- URI filenames: https://www.sqlite.org/uri.html
- Opening databases: https://sqlite.org/c3ref/open.html
- PRAGMA documentation: https://sqlite.org/pragma.html

### 13.2 Why not mutate Apple Notes DB

Do not write to `NoteStore.sqlite`. Do not add columns. Do not checkpoint the live database. Do not modify rows. The application should be read-only with respect to Apple Notes.

### 13.3 Example metadata query

This is an illustrative query only. The implementation must introspect actual schema because Apple changes private Notes schema over time.

```sql
SELECT
    n.Z_PK AS object_pk,
    n.ZIDENTIFIER AS note_uuid,
    n.ZTITLE1 AS title,
    n.ZSNIPPET AS snippet,
    n.ZCREATIONDATE1 AS created_coredata,
    n.ZMODIFICATIONDATE1 AS modified_coredata,
    f.Z_PK AS folder_pk,
    f.ZIDENTIFIER AS folder_uuid,
    COALESCE(f.ZTITLE2, f.ZTITLE1) AS folder_name
FROM ZICCLOUDSYNCINGOBJECT n
LEFT JOIN ZICCLOUDSYNCINGOBJECT f
    ON f.Z_PK = n.ZFOLDER
WHERE
    n.ZNOTEDATA IS NOT NULL
    AND n.ZIDENTIFIER IS NOT NULL;
```

### 13.4 Core Data timestamp conversion

Apple/Core Data timestamps are commonly seconds since 2001-01-01 00:00:00 UTC, not Unix epoch. Convert with:

```text
unix_timestamp = coredata_timestamp + 978307200
```

In SQL:

```sql
datetime(n.ZMODIFICATIONDATE1 + 978307200, 'unixepoch', 'localtime')
```

Reference:  
https://www.epochconverter.com/coredata

### 13.5 Schema introspection

Run something like:

```sql
SELECT name, sql
FROM sqlite_master
WHERE type = 'table'
ORDER BY name;
```

Also inspect columns:

```sql
PRAGMA table_info(ZICCLOUDSYNCINGOBJECT);
PRAGMA table_info(ZICNOTEDATA);
```

The tool should log schema information on startup and provide a debug command:

```bash
notes2myicor inspect-schema
```

---

## 14. Snapshot Strategy

### 14.1 Do we need to snapshot for metadata polling?

No, not strictly. A read-only live query is acceptable for quick change detection.

### 14.2 Do we need to snapshot for full extraction?

Recommended, yes.

Apple Core Data SQLite stores commonly use WAL mode. Apple’s Core Data QA1809 explains that WAL mode keeps the main store file untouched while appending transactions to the `-wal` file, and copying only the main SQLite file can cause data loss/inconsistency.

Reference:  
https://developer.apple.com/library/archive/qa/qa1809/_index.html

For this project, the risk is not modifying Apple Notes, but getting an inconsistent view between:

```text
NoteStore.sqlite
NoteStore.sqlite-wal
NoteStore.sqlite-shm
media files / drawings / attachments
```

### 14.3 Best compromise

```text
Fast polling:
  Read live database read-only.

If changes detected:
  Create a work snapshot/copy for full parse/render.
```

### 14.4 Snapshot implementation options

Options:

1. Use SQLite backup API for the database file, then copy supporting media folders.
2. Copy the whole `group.com.apple.notes` folder, including `-wal`/`-shm`, into a work directory.
3. If using Apple Cloud Notes Parser initially, use its `--mac` behavior, which computes the path to `NoteStore.sqlite`, copies it to output, and opens the copy.

Be careful: copying only `NoteStore.sqlite` and ignoring `NoteStore.sqlite-wal` can miss committed transactions still in the WAL.

---

## 15. State Database Design

### 15.1 Purpose

The application needs its own state DB so it knows:

- which notes have already been exported,
- which notes changed,
- where the PDF was written,
- whether a note is missing/deleted,
- whether a note moved out of scope,
- whether previous export attempts failed.

Use a separate SQLite database, for example:

```text
~/Library/Application Support/Notes2MyICOR/state.sqlite
```

### 15.2 `notes_state` table

```sql
CREATE TABLE IF NOT EXISTS notes_state (
    note_uuid TEXT PRIMARY KEY,

    apple_object_pk INTEGER,
    account_name TEXT,
    account_uuid TEXT,
    folder_uuid TEXT,
    folder_path TEXT,
    folder_name TEXT,

    title TEXT,
    snippet TEXT,

    created_coredata REAL,
    modified_coredata REAL,
    created_at_utc TEXT,
    modified_at_utc TEXT,

    last_seen_at TEXT NOT NULL,
    last_exported_at TEXT,
    last_successful_scan_id TEXT,

    content_hash TEXT,
    metadata_hash TEXT,

    pdf_path TEXT,
    sidecar_json_path TEXT,

    export_status TEXT NOT NULL DEFAULT 'pending',
    export_error TEXT,

    is_deleted INTEGER NOT NULL DEFAULT 0,
    deleted_detected_at TEXT,

    is_in_scope INTEGER NOT NULL DEFAULT 1,
    out_of_scope_detected_at TEXT,

    missing_scan_count INTEGER NOT NULL DEFAULT 0,
    first_missing_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_notes_state_modified
ON notes_state(modified_coredata);

CREATE INDEX IF NOT EXISTS idx_notes_state_deleted
ON notes_state(is_deleted);

CREATE INDEX IF NOT EXISTS idx_notes_state_in_scope
ON notes_state(is_in_scope);
```

### 15.3 `scan_runs` table

```sql
CREATE TABLE IF NOT EXISTS scan_runs (
    scan_id TEXT PRIMARY KEY,
    started_at TEXT NOT NULL,
    completed_at TEXT,
    status TEXT NOT NULL,
    notes_seen INTEGER DEFAULT 0,
    notes_new INTEGER DEFAULT 0,
    notes_modified INTEGER DEFAULT 0,
    notes_exported INTEGER DEFAULT 0,
    notes_failed INTEGER DEFAULT 0,
    notes_missing INTEGER DEFAULT 0,
    error TEXT
);
```

### 15.4 `sync_roots` table

```sql
CREATE TABLE IF NOT EXISTS sync_roots (
    root_id TEXT PRIMARY KEY,
    account_name TEXT NOT NULL,
    account_uuid TEXT,
    folder_path TEXT NOT NULL,
    folder_uuid TEXT,
    recursive INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    last_resolved_at TEXT
);
```

---

## 16. Change Detection Algorithm

### 16.1 Classifications

Each scan should classify notes as:

```text
NEW
MODIFIED
METADATA_CHANGED
UNCHANGED
OUT_OF_SCOPE
MISSING_POSSIBLY_DELETED
DELETED_AFTER_GRACE
EXPORT_FAILED
```

### 16.2 Basic algorithm

```text
1. Read current metadata from Apple Notes.
2. Resolve configured account/folder scope.
3. Build current in-scope note set.
4. For each current in-scope note:
      if UUID not in state DB:
          mark NEW
      else if modified timestamp changed:
          mark MODIFIED
      else if title/folder metadata changed:
          mark METADATA_CHANGED
      else:
          mark UNCHANGED
5. For notes in state DB that are no longer in current in-scope set:
      if note still exists elsewhere:
          mark OUT_OF_SCOPE
      else:
          increment missing_scan_count
          if count >= grace threshold:
              mark DELETED_AFTER_GRACE
6. Export NEW and MODIFIED notes.
7. Optionally update/rename output for METADATA_CHANGED notes.
8. Update state DB only after successful processing.
```

### 16.3 Use content hash, not just modification date

After reconstructing the note body, compute a content hash.

Inputs can include:

```text
title
folder UUID/path
HTML body
plaintext
embedded object identifiers
embedded object metadata
```

If Apple Notes reports a modified timestamp change but the content hash is unchanged, the tool can avoid rewriting the PDF.

If the timestamp appears unchanged but the content hash changed, re-export anyway.

### 16.4 Pseudocode

```swift
func syncOnce() throws {
    let scanID = UUID().uuidString
    try stateDB.beginScan(scanID)

    let inventory = try notesReader.readCurrentInventory()
    let scope = try folderResolver.resolve(config.scope, inventory: inventory)
    let inScopeNotes = inventory.notes.filter { scope.allowedFolderIDs.contains($0.folderID) }

    let existingState = try stateDB.loadAllNotes()
    let classifications = ChangeClassifier.classify(
        currentNotes: inScopeNotes,
        allCurrentNotes: inventory.notes,
        previousState: existingState,
        allowedFolderIDs: scope.allowedFolderIDs,
        missingGraceCount: config.polling.missingScanGraceCount
    )

    let candidates = classifications.filter { $0.requiresExport }

    if candidates.isEmpty {
        try stateDB.finishScan(scanID, status: .success)
        return
    }

    let parseSnapshot = try snapshotter.createSnapshotIfNeeded()
    let parsedNotes = try parser.parse(snapshot: parseSnapshot, noteUUIDs: candidates.map(\.noteUUID))

    for candidate in candidates {
        do {
            let parsed = try parsedNotes.require(candidate.noteUUID)
            let contentHash = Hashing.hash(parsed)

            if stateDB.contentHash(candidate.noteUUID) == contentHash {
                try stateDB.updateMetadataOnly(candidate.note)
                continue
            }

            let html = try htmlRenderer.render(parsed)
            let pdfData = try pdfRenderer.render(html)
            let output = try outputWriter.writePDF(pdfData, for: parsed)
            try sidecarWriter.write(parsed, output: output)

            try stateDB.markExportSuccess(
                note: candidate.note,
                pdfPath: output.pdfPath,
                contentHash: contentHash,
                scanID: scanID
            )
        } catch {
            try stateDB.markExportFailure(candidate.noteUUID, error: error)
            logger.error("Failed exporting \(candidate.noteUUID): \(error)")
        }
    }

    try deletionPolicy.process(classifications, stateDB: stateDB)
    try stateDB.finishScan(scanID, status: .success)
}
```

---

## 17. Deletion and Out-of-Scope Handling

### 17.1 Do not automatically delete PDFs

The app should never permanently delete exported PDFs automatically. Deleted Apple Notes should move exported PDFs to a deleted/archive folder or mark them in state.

Recommended output folders:

```text
Apple Notes/
  Active/
  _Deleted/
    Recently Deleted/
    Permanently Missing/
  _OutOfScope/
  _Failed/
```

### 17.2 Soft delete / Recently Deleted

Apple Notes moves deleted notes to Recently Deleted for a recovery period before permanent removal.

Apple reference:  
https://support.apple.com/guide/notes/delete-a-note-not5585d71a8/mac

If the note still exists but is in a Recently Deleted folder, mark it as soft-deleted and optionally move the PDF to `_Deleted/Recently Deleted`.

### 17.3 Hard delete / missing entirely

If a note UUID previously exported no longer appears in the full Apple Notes inventory:

```text
missing_scan_count += 1
```

Only after a grace threshold, for example 3 successful scans, mark it deleted.

Recommended policy:

```text
missing for 1 scan: do nothing except increment count
missing for 2 scans: keep waiting
missing for 3 successful full scans: mark deleted and move PDF to _Deleted/Permanently Missing
```

### 17.4 Out of scope

If a note still exists in Apple Notes but has moved outside the configured folder tree:

```text
mark is_in_scope = 0
set out_of_scope_detected_at
move PDF to _OutOfScope, or leave it and mark state only
```

Do not mark it deleted.

---

## 18. Parser/Reconstructor Design

### 18.1 Initial implementation choice

There are two viable implementation modes:

#### Mode A: Swift app uses Apple Cloud Notes Parser initially

Pros:

- Fastest path to working prototype.
- Uses known parser logic.
- Good for validating output.

Cons:

- Requires Ruby and dependencies.
- Less self-contained.
- Output may need filtering/post-processing.

#### Mode B: Native Swift parser

Pros:

- Self-contained macOS utility.
- Better long-term UX.
- Easier to distribute as a native app/CLI.

Cons:

- Requires reimplementation of private Apple Notes protobuf parsing.
- More edge cases.
- More maintenance when Apple changes schema.

### 18.2 Recommended staged approach

1. **Prototype:** Swift sync engine + Apple Cloud Notes Parser subprocess.
2. **MVP:** Swift handles metadata/state/rendering; parser still external.
3. **Native v1:** Swift decodes enough note body data for the user’s normal handwritten/text/image notes.
4. **Native v2:** Add tables, drawings, embedded PDFs/scans, improved fidelity.

### 18.3 Intermediate note model

Do not render directly from protobuf data. Convert decoded data into an internal neutral model.

Example:

```swift
struct NoteDocument: Codable {
    var uuid: String
    var title: String
    var accountName: String
    var folderPath: String
    var createdAt: Date
    var modifiedAt: Date
    var blocks: [Block]
    var embeddedObjects: [EmbeddedObject]
}

enum Block: Codable {
    case heading(level: Int, inlines: [Inline])
    case paragraph(inlines: [Inline])
    case checklist(checked: Bool, inlines: [Inline])
    case table(Table)
    case image(EmbeddedObjectRef)
    case drawing(EmbeddedObjectRef)
    case attachment(EmbeddedObjectRef)
    case horizontalRule
}

enum Inline: Codable {
    case text(String, attributes: TextAttributes)
    case link(text: String, url: String)
}
```

### 18.4 Embedded objects

Expect embedded objects to be the hardest part.

Possible objects:

```text
images
Apple Pencil drawings
scanned documents
PDF attachments
tables
links
checklists
thumbnails
shared-note metadata
```

Ciofeca Forensics warns that embedded objects are easy to do wrong and each type can be represented differently.

Reference:  
https://www.ciofecaforensics.com/2020/01/13/apple-notes-revisited-easy-embedded-objects/

### 18.5 Locked notes

Skip locked notes in v1.

Apple Cloud Notes Parser can decrypt notes if the password is known and the device passcode is not used, but says iOS 16 passcode-based locked notes are not handled.

Reference:  
https://github.com/threeplanetssoftware/apple_cloud_notes_parser

The app should report locked/unsupported notes clearly:

```text
Skipped locked note: <title> (<uuid>)
Reason: locked notes are not supported in this version.
```

---

## 19. HTML Rendering

### 19.1 Why HTML first

HTML is the best intermediate format:

- It represents rich text naturally.
- It supports images, tables, checklists and links.
- It can be previewed/debugged independently.
- It can be converted to PDF via WebKit.
- It can be saved alongside PDFs for debugging.

### 19.2 HTML page structure

Each generated note HTML should include metadata header and body.

Example:

```html
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Note Title</title>
  <style>
    @page { size: A4; margin: 14mm; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
      font-size: 12pt;
      line-height: 1.35;
    }
    img {
      max-width: 100%;
      height: auto;
      page-break-inside: avoid;
    }
    table {
      border-collapse: collapse;
      width: 100%;
    }
    td, th {
      border: 1px solid #aaa;
      padding: 4px 6px;
      vertical-align: top;
    }
    pre, code { white-space: pre-wrap; }
    h1, h2, h3 { page-break-after: avoid; }
    .note-meta {
      color: #666;
      font-size: 10pt;
      border-bottom: 1px solid #ddd;
      margin-bottom: 12px;
      padding-bottom: 6px;
    }
  </style>
</head>
<body>
  <div class="note-meta">
    <strong>Apple Notes</strong><br>
    Folder: iCloud / myICOR Capture<br>
    Modified: 2026-05-29 15:21:00 +09:30<br>
    UUID: ...
  </div>

  <h1>Note Title</h1>
  <!-- rendered note body -->
</body>
</html>
```

### 19.3 Store debug HTML optionally

For debugging, optionally write HTML next to the PDF:

```text
2026-05-29 - My Note - ABC123.pdf
2026-05-29 - My Note - ABC123.html
2026-05-29 - My Note - ABC123.json
```

---

## 20. PDF Rendering

### 20.1 Swift PDF rendering path

Use `WKWebView.createPDF(configuration:completionHandler:)` to generate PDF data from rendered HTML.

Apple reference:  
https://developer.apple.com/documentation/webkit/wkwebview/createpdf%28configuration:completionhandler:%29

Use `WKPDFConfiguration` for page/rect configuration:

https://developer.apple.com/documentation/webkit/wkpdfconfiguration

### 20.2 PDF manipulation

Use `PDFKit` and `PDFDocument` for:

- writing PDF files,
- appending embedded PDF pages,
- adding/removing pages,
- adding metadata,
- merging rendered note PDF with extracted PDF attachments.

Apple references:

- PDFKit: https://developer.apple.com/documentation/pdfkit
- PDFDocument: https://developer.apple.com/documentation/pdfkit/pdfdocument
- PDFDocument `insert(_:at:)`: https://developer.apple.com/documentation/pdfkit/pdfdocument/insert%28_:at:%29
- PDFDocument `write(to:)`: https://developer.apple.com/documentation/pdfkit/pdfdocument/write%28to:withoptions:%29

### 20.3 Embedded PDFs/scans

Apple Notes' own manual export may only include first page of embedded multipage PDFs/scans. This tool should avoid that limitation where possible.

Recommended behavior:

1. Render the visible note body to PDF.
2. If the note contains embedded PDF attachments or scans and the full PDF file can be extracted, append all pages to the rendered PDF or save them as separate PDFs.

Configuration option:

```toml
append_embedded_pdfs = true
embedded_pdf_mode = "append" # append | separate | link-only
```

Possible output:

```text
My Note - ABC123.pdf
My Note - ABC123 - attachment 1.pdf
```

or combined:

```text
My Note - ABC123.pdf
```

with note body pages followed by attachment pages.

---

## 21. Output Naming

### 21.1 Requirements

Output names should be readable but stable enough to avoid duplicate confusion.

Use UUID in filenames. Do not rely only on title.

### 21.2 Recommended filename

```text
YYYY-MM-DD - Safe Note Title - <uuid-short>.pdf
```

Example:

```text
2026-05-29 - myICOR sketch workflow - 7E4A91C2D8F1.pdf
```

### 21.3 Alternative stable filename

For systems that dislike renames:

```text
<uuid>.pdf
```

Example:

```text
7E4A91C2-D8F1-4A1E-9C4B-123456789ABC.pdf
```

### 21.4 Recommendation

Use hybrid:

```text
<uuid-short> - <safe-title>.pdf
```

This keeps a stable identity even if the title changes.

### 21.5 Safe filename rules

Replace these characters:

```text
: / \ | ? * " < > newline tab
```

Limit filename length, for example 120 characters before extension.

---

## 22. Sidecar JSON

Write a sidecar `.json` file next to each PDF.

Example:

```json
{
  "source": "Apple Notes",
  "note_uuid": "7E4A91C2-D8F1-4A1E-9C4B-123456789ABC",
  "title": "myICOR sketch workflow",
  "account": "iCloud",
  "folder_path": "myICOR Capture/Sketches",
  "created_at": "2026-05-29T10:14:02+09:30",
  "modified_at": "2026-05-29T10:25:44+09:30",
  "exported_at": "2026-05-29T10:26:01+09:30",
  "content_hash": "sha256:...",
  "pdf_path": "...",
  "parser_version": "...",
  "warnings": []
}
```

This is useful for myICOR, debugging, re-ingestion and future migrations.

---

## 23. Launch / Scheduling

### 23.1 CLI command

The app should support manual execution:

```bash
notes2myicor sync --once
```

and inspect commands:

```bash
notes2myicor accounts
notes2myicor folders --account "iCloud"
notes2myicor inspect-schema
notes2myicor status
```

### 23.2 LaunchAgent

Use `launchd` for periodic execution.

Apple launchd reference:  
https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html

Example LaunchAgent:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.example.notes2myicor</string>

  <key>ProgramArguments</key>
  <array>
    <string>/Users/username/bin/notes2myicor</string>
    <string>sync</string>
    <string>--once</string>
  </array>

  <key>StartInterval</key>
  <integer>300</integer>

  <key>RunAtLoad</key>
  <true/>

  <key>StandardOutPath</key>
  <string>/tmp/notes2myicor.out.log</string>

  <key>StandardErrorPath</key>
  <string>/tmp/notes2myicor.err.log</string>
</dict>
</plist>
```

Load:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.notes2myicor.plist
launchctl kickstart -k gui/$(id -u)/com.example.notes2myicor
```

Unload:

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.example.notes2myicor.plist
```

### 23.3 Poll interval

Recommended default:

```text
300 seconds / 5 minutes
```

For development:

```text
30-60 seconds
```

---

## 24. Open Source Strategy

### 24.1 New project vs fork

Prefer a new project, not a direct fork where Ruby is slowly replaced with Swift/Rust.

Suggested repo names:

```text
apple-notes-pdf-sync
notes2myicor
apple-notes-swift-exporter
```

### 24.2 License

Recommended license:

```text
MIT
```

or:

```text
MIT OR Apache-2.0
```

If using Apple Cloud Notes Parser code or substantial derived logic, preserve MIT notices.

### 24.3 README positioning

Suggested README summary:

```text
Notes2MyICOR is a macOS utility that watches locally synced Apple Notes, detects new and modified notes under a configured folder tree, reconstructs them, and writes PDFs plus sidecar metadata to a designated folder.

It is intended for personal knowledge-base workflows where Apple Notes is used for handwriting, sketches and diagrams on iPad, and PDFs are needed for folder-based ingestion.
```

### 24.4 Privacy statement

Because this tool reads Apple Notes, include an explicit privacy statement:

```text
This tool reads the local Apple Notes database on your Mac. It does not authenticate to iCloud, does not send notes to external servers, and does not modify Apple Notes. All output is written locally to the configured folder.
```

---

## 25. CLI Design

Suggested CLI:

```bash
notes2myicor init
notes2myicor accounts
notes2myicor folders --account "iCloud"
notes2myicor inspect-schema
notes2myicor scan
notes2myicor sync --once
notes2myicor sync --watch
notes2myicor status
notes2myicor reset-state --note-uuid <uuid>
notes2myicor reexport --note-uuid <uuid>
notes2myicor reexport --all
notes2myicor install-launch-agent
notes2myicor uninstall-launch-agent
```

Example sync:

```bash
notes2myicor sync \
  --account "iCloud" \
  --folder "myICOR Capture" \
  --recursive \
  --output "$HOME/myICOR/Inbox/Apple Notes"
```

---

## 26. Error Handling

### 26.1 Per-note isolation

One bad note should not stop the whole run.

If export fails:

```text
state.export_status = failed
state.export_error = error message
write failure to log
continue with next note
```

### 26.2 Common errors

Possible errors:

```text
Apple Notes database not found
No Full Disk Access / permission denied
Configured account not found
Configured folder path not found
Schema columns not found
Unsupported note object type
Failed to decompress ZDATA
Failed to decode protobuf
Embedded object missing from filesystem
WKWebView PDF rendering timeout
PDFKit merge failure
Output folder not writable
```

### 26.3 Recommended debug outputs

Have a debug mode that can write:

```text
raw metadata JSON
parser JSON
generated HTML
warnings JSON
schema dump
```

---

## 27. Testing Strategy

### 27.1 Test note corpus

Create a controlled Apple Notes folder named:

```text
myICOR Capture Test
```

Add notes covering:

```text
plain text
rich text
headings
lists
checklists
links
tables
images
handwritten sketch / Apple Pencil drawing
scanned document
PDF attachment
long note spanning multiple pages
note renamed after export
note modified after export
note moved into scope
note moved out of scope
note deleted
note in subfolder
```

### 27.2 Comparison against Apple Cloud Notes Parser

For each test note:

```text
Apple Cloud Notes Parser JSON/HTML
vs
Swift parser JSON/HTML/PDF
```

Compare:

```text
UUID
title
folder path
created/modified timestamps
plaintext
HTML body
embedded object count
export warnings
```

### 27.3 Regression tests

Automated tests should cover:

```text
folder path resolution
descendant folder selection
new note classification
modified note classification
metadata-only change
moved out of scope
deleted grace policy
filename sanitisation
sidecar JSON creation
state DB migration
```

### 27.4 Manual acceptance test

End-to-end:

1. Create a note on iPad in the configured Apple Notes folder.
2. Add handwriting/sketch/diagram.
3. Wait for iCloud sync to Mac.
4. Run `notes2myicor sync --once`.
5. Confirm PDF appears in output folder.
6. Modify the same note on iPad.
7. Run sync again.
8. Confirm PDF is updated/replaced.
9. Move note out of folder.
10. Confirm state marks out-of-scope.
11. Delete note.
12. Confirm PDF is preserved/moved, not destroyed.

---

## 28. Security and Privacy

### 28.1 Data sensitivity

Apple Notes may contain highly personal data. The app should:

- Run locally.
- Avoid network access by default.
- Never send note content externally.
- Avoid verbose logging of note bodies unless debug mode is enabled.
- Store logs carefully.
- Provide an easy way to delete generated debug files.

### 28.2 Read-only design

The app should never write to Apple’s Notes database or media folders.

### 28.3 State DB sensitivity

The state DB contains note titles, snippets, folder names and output paths. Treat it as private user data.

---

## 29. Known Risks and Limitations

### 29.1 Private schema

Apple Notes uses a private schema. Apple can change table/column names or protobuf structure in future macOS/iOS releases.

Ciofeca Forensics documented schema changes in iOS 18, including new columns in `ZICCLOUDSYNCINGOBJECT`.

Reference:  
https://www.ciofecaforensics.com/2024/12/10/ios18-notes/

### 29.2 Visual fidelity

A reconstructed HTML/PDF may not be pixel-identical to Apple Notes' own display.

For myICOR ingestion, semantic fidelity may be more important than pixel-perfect visual fidelity.

### 29.3 Handwriting/drawings

Handwriting and sketches may be stored as embedded drawing objects. These are likely harder than plain text and images. Implement support incrementally and test heavily.

### 29.4 Locked notes

Skip locked notes in v1.

### 29.5 Sync races

iCloud sync may not complete instantly. A note created on iPad may not appear on the Mac immediately. The app should tolerate this and pick it up on a later run.

### 29.6 Recently Deleted behavior

Deleted notes may remain in Recently Deleted before permanent removal. Treat this as a soft-delete state.

---

## 30. Minimal Viable Product

### MVP goal

Export new and modified Apple Notes under one configured iCloud folder tree to PDF.

### MVP scope

```text
Mac only
Swift CLI
Read live metadata DB read-only
Config file
State SQLite DB
Folder-scoped sync
Apple Cloud Notes Parser subprocess for extraction
HTML-to-PDF rendering using WKWebView or external parser HTML
PDF output
Sidecar JSON
Deletion/out-of-scope state handling
LaunchAgent plist generation optional
```

### MVP intentionally skips

```text
native protobuf parser
locked notes
perfect embedded object support
GUI
App Store sandboxing
cross-platform support
```

### MVP success criterion

A user can create a handwritten/sketched note in a configured Apple Notes folder on iPad, and within a polling interval a PDF is produced in the configured folder on the Mac.

---

## 31. Suggested Development Milestones

### Milestone 1: Discovery CLI

Commands:

```bash
notes2myicor accounts
notes2myicor folders --account "iCloud"
notes2myicor notes --account "iCloud" --folder "myICOR Capture" --recursive
```

Deliverables:

- Read Apple Notes metadata DB.
- Resolve accounts/folders.
- Print notes under selected folder tree.
- No export yet.

### Milestone 2: State DB and change detection

Deliverables:

- State DB schema.
- New/modified/unchanged classification.
- Missing/out-of-scope detection.
- Status command.

### Milestone 3: Apple Cloud Notes Parser integration

Deliverables:

- Run ACNP as subprocess.
- Parse its JSON output.
- Match parser notes by UUID.
- Extract HTML/assets for changed notes.

### Milestone 4: PDF rendering

Deliverables:

- Render HTML to PDF.
- Write PDFs to output folder.
- Write sidecar JSON.
- Update state after success.

### Milestone 5: Deletion and move handling

Deliverables:

- Soft-delete handling.
- Missing-note grace policy.
- Out-of-scope handling.
- Preserve/move PDFs, never destroy automatically.

### Milestone 6: Native Swift parser proof of concept

Deliverables:

- Decode `ZICNOTEDATA.ZDATA` for simple text notes.
- Compare against ACNP.
- Render simple notes without ACNP.

### Milestone 7: Embedded object support

Deliverables:

- Images.
- Drawings/sketches.
- Tables.
- Embedded PDF/scans.

### Milestone 8: Packaging and usability

Deliverables:

- Install command.
- LaunchAgent install/uninstall.
- Logging folder.
- Full Disk Access instructions.
- Optional menu bar app.

---

## 32. Example Initial Commands Using Apple Cloud Notes Parser

Install/reference project:

```bash
mkdir -p ~/src
cd ~/src
git clone https://github.com/threeplanetssoftware/apple_cloud_notes_parser.git
cd apple_cloud_notes_parser
bundle install
```

Run against local Mac Notes folder:

```bash
ruby notes_cloud_ripper.rb \
  --mac "$HOME/Library/Group Containers/group.com.apple.notes" \
  --output-dir "$HOME/Library/Application Support/Notes2MyICOR/acnp-output" \
  --one-output-folder \
  --individual-files \
  --uuid \
  --retain-display-order
```

Use JSON output to identify notes by UUID and render only changed notes.

---

## 33. Developer FAQ

### Q: Does the app need to log into iCloud?

No. It reads the local Apple Notes store already synced by macOS.

### Q: Is the Apple Notes database officially documented?

No. It is private. Use defensive code and expect schema changes.

### Q: Can we query by date/time?

Yes, for metadata. Use creation/modification fields from Apple Notes metadata tables. But do not rely only on timestamps; also track UUID and content hash.

### Q: Do we need a snapshot just to query new notes?

No. Live read-only metadata query is acceptable.

### Q: Do we need a snapshot for full extraction?

Recommended. Full extraction touches SQLite data plus associated media/assets. A snapshot reduces race conditions and WAL inconsistency issues.

### Q: How should deleted notes be handled?

Conservatively. Do not delete PDFs automatically. Mark state and move output to `_Deleted` after a grace period.

### Q: How do we handle notes moved outside the configured folder?

Mark them `out_of_scope`, not deleted.

### Q: Can we filter to a folder and subfolders only?

Yes. Resolve the configured folder to a folder UUID, collect descendants, and include only notes whose folder UUID is in that set.

### Q: Should the app use AppleScript?

Not for the core parser. AppleScript can interact with Notes, but it is not ideal for robust extraction/rendering. It may be useful only for small helper actions or diagnostics.

### Q: Should the app use Apple Notes manual PDF export?

No. It is manual and has limitations around embedded multipage scans/PDFs.

### Q: Should we build in Swift or Rust?

Swift is recommended for this Mac-specific PDF/export utility. Rust is feasible for a CLI/parser, but Swift integrates more naturally with WebKit, PDFKit, macOS permissions, and optional UI.

### Q: Is this legal to release open source?

Yes, provided the project only reads the user’s local data and complies with licenses. Apple Cloud Notes Parser is MIT licensed, but include its copyright/license notice if code or substantial logic is reused.

### Q: What is the biggest technical risk?

Apple Notes' private schema and embedded-object formats, especially drawings/sketches and scans.

---

## 34. Reference Links

### Apple Notes / Apple Support

- Export or print notes on iPhone:  
  https://support.apple.com/guide/iphone/export-or-print-notes-iphdf551cfa2/ios

- Export or print notes on iPad:  
  https://support.apple.com/guide/ipad/export-or-print-notes-ipad50c393a8/ipados

- Use iCloud with Notes:  
  https://support.apple.com/guide/icloud/what-you-can-do-with-icloud-and-notes-mm2d069f7097/icloud

- Delete a note on Mac / Recently Deleted behavior:  
  https://support.apple.com/guide/notes/delete-a-note-not5585d71a8/mac

### Apple Developer

- Core Data WAL mode QA1809:  
  https://developer.apple.com/library/archive/qa/qa1809/_index.html

- LaunchAgents / launchd jobs:  
  https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html

- WKWebView `createPDF`:  
  https://developer.apple.com/documentation/webkit/wkwebview/createpdf%28configuration:completionhandler:%29

- WKPDFConfiguration:  
  https://developer.apple.com/documentation/webkit/wkpdfconfiguration

- PDFKit:  
  https://developer.apple.com/documentation/pdfkit

- PDFDocument:  
  https://developer.apple.com/documentation/pdfkit/pdfdocument

- PDFDocument `insert(_:at:)`:  
  https://developer.apple.com/documentation/pdfkit/pdfdocument/insert%28_:at:%29

- PDFDocument `write(to:)`:  
  https://developer.apple.com/documentation/pdfkit/pdfdocument/write%28to:withoptions:%29

- App sandbox / protecting user data:  
  https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox

- Accessing files from macOS app sandbox:  
  https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox

### Apple Cloud Notes Parser and forensic research

- Apple Cloud Notes Parser GitHub:  
  https://github.com/threeplanetssoftware/apple_cloud_notes_parser

- Apple Cloud Notes Parser JSON schema:  
  https://github.com/threeplanetssoftware/apple_cloud_notes_parser/blob/master/JSON.md

- Apple Cloud Notes Parser license:  
  https://github.com/threeplanetssoftware/apple_cloud_notes_parser/blob/master/LICENSE

- Apple Cloud Notes Parser releases:  
  https://github.com/threeplanetssoftware/apple_cloud_notes_parser/releases

- Ciofeca Forensics: Revisiting Apple Notes, Improved Note Parsing:  
  https://www.ciofecaforensics.com/2020/01/10/apple-notes-revisited/

- Ciofeca Forensics: Embedded Objects:  
  https://www.ciofecaforensics.com/2020/01/13/apple-notes-revisited-easy-embedded-objects/

- Ciofeca Forensics: Apple Notes in iOS 18:  
  https://www.ciofecaforensics.com/2024/12/10/ios18-notes/

### Swift libraries

- SwiftProtobuf:  
  https://github.com/apple/swift-protobuf

- GRDB.swift:  
  https://github.com/groue/GRDB.swift

### SQLite

- SQLite URI filenames:  
  https://www.sqlite.org/uri.html

- SQLite open database API:  
  https://sqlite.org/c3ref/open.html

- SQLite PRAGMA documentation:  
  https://sqlite.org/pragma.html

- SQLite backup API:  
  https://www.sqlite.org/backup.html

- SQLite WAL documentation:  
  https://www.sqlite.org/wal.html

### Timestamp reference

- Core Data timestamp converter:  
  https://www.epochconverter.com/coredata

### Rust alternatives, if needed

- Prost, Rust Protocol Buffers:  
  https://github.com/tokio-rs/prost

- flate2 crate:  
  https://docs.rs/flate2

- rusqlite crate:  
  https://github.com/rusqlite/rusqlite

---

## 35. Suggested Developer Acceptance Criteria

A developer can consider the project successful when:

1. The app can list Apple Notes accounts.
2. The app can list folder trees under `iCloud`.
3. The app can select one folder and include subfolders.
4. The app can detect notes created after the last run.
5. The app can detect notes modified after the last export.
6. The app can render a changed note to PDF.
7. The app writes the PDF to a configured output folder.
8. The app writes sidecar JSON with UUID, title, folder, modified timestamp and content hash.
9. The app does not re-export unchanged notes.
10. The app detects moved-out-of-scope notes.
11. The app handles missing/deleted notes conservatively.
12. The app never modifies Apple Notes data.
13. The app can be run manually and via LaunchAgent.
14. The app has useful logs and error messages.
15. The app has a test corpus covering text, handwriting/sketches, images, tables and deletion/move scenarios.

---

## 36. Final Recommendation

Build `Notes2MyICOR` as a **Swift macOS utility** with a CLI-first architecture and optional menu bar UI later.

Use Apple Cloud Notes Parser as the immediate reference implementation and, if necessary, as a subprocess in the first prototype. Then progressively implement the needed parser logic natively in Swift using `SwiftProtobuf`, focusing only on the user’s actual requirements:

```text
Mac local iCloud Notes only
folder-scoped extraction
new/modified detection
HTML/PDF export
sidecar JSON
safe deletion handling
myICOR folder output
```

Do not attempt to build a full forensic replacement for Apple Cloud Notes Parser unless the project later grows beyond the personal myICOR workflow.

**Overall confidence:** 0.87. The architecture is solid and aligns with existing Apple Notes storage research. The main uncertainty is long-term compatibility with Apple’s private Notes schema and complete fidelity for handwritten drawings, scans and embedded objects.
