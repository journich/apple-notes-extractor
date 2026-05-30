# Apple Notes to PDF Sync Utility: Implementation Stages

This document breaks the `Notes2MyICOR` / `AppleNotesPDFSync` project into discrete stages that can be completed one at a time.

The intended way to use this document is to ask:

```text
Complete Stage 1
Complete Stage 2
...
```

Each stage has:

- a goal,
- concrete implementation tasks,
- unit tests,
- integration or manual tests,
- acceptance criteria.

The stages are ordered to reduce risk. The early stages prove access to the local Apple Notes database, folder scoping, and state tracking before investing heavily in PDF rendering or a native Apple Notes parser.

---

## Stage 0: Project Bootstrap and Engineering Baseline

### Goal

Create the initial Swift CLI project structure, testing setup, logging, configuration loading, and basic developer commands.

This stage should not read Apple Notes yet. It establishes the foundation used by later stages.

### Implementation tasks

- Create a Swift package.
- Add CLI executable target, for example `notes2myicor`.
- Add core library target, for example `Notes2MyICORCore`.
- Add test target.
- Add basic CLI command routing.
- Add `--help` output.
- Add app version command.
- Add structured logging helper.
- Add config file model.
- Add default config path handling.
- Add path expansion for `~`.
- Add basic application support directory creation.
- Add a small README or developer note explaining how to build and test.

Suggested commands after this stage:

```bash
notes2myicor --help
notes2myicor version
notes2myicor init
```

### Unit tests

- Config defaults are correct.
- Config can be loaded from TOML or JSON, depending on chosen config format.
- `~` path expansion works.
- Missing config reports a clear error.
- Invalid config reports a clear error.
- App support directory path is computed correctly.
- Logger can write without throwing.

### Integration/manual tests

- `swift test` passes.
- `swift run notes2myicor --help` prints available commands.
- `swift run notes2myicor version` prints a version.
- `swift run notes2myicor init` creates a config file without overwriting an existing config unless explicitly requested.

### Acceptance criteria

- The project builds from a clean checkout.
- Tests run with one command.
- The CLI exists and can be invoked.
- No Apple Notes data is touched yet.

---

## Stage 1: Apple Notes Store Discovery

### Goal

Read the local Apple Notes store in read-only mode and expose diagnostics about the database schema.

This stage proves that the tool can find and inspect:

```text
~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite
```

without modifying it.

### Implementation tasks

- Add Apple Notes group container path resolution.
- Add read-only SQLite opening using URI mode where practical.
- Set `PRAGMA query_only = ON`.
- Add schema inspection command.
- List tables from `sqlite_master`.
- List columns for key tables such as `ZICCLOUDSYNCINGOBJECT` and `ZICNOTEDATA`.
- Detect missing Apple Notes database.
- Detect permission denied / Full Disk Access issues.
- Make schema output useful for debugging without dumping note content.

Suggested command:

```bash
notes2myicor inspect-schema
```

### Unit tests

- Read-only database connection builder produces expected URI/path.
- Missing database error is clear and actionable.
- Permission-style errors are mapped to useful messages.
- Schema inspector parses table and column metadata from a fixture SQLite DB.
- Schema inspector handles missing expected tables gracefully.

### Integration/manual tests

- Run `inspect-schema` against a fixture SQLite DB.
- Run `inspect-schema` against the real Apple Notes database on the Mac.
- Confirm the command does not create or modify files in the Apple Notes container.
- Confirm the tool logs schema data but not note body content.

### Acceptance criteria

- The CLI can inspect the local Notes schema.
- The real Notes DB is opened read-only.
- Errors explain whether the issue is missing data, permissions, or unsupported schema.

---

## Stage 2: Accounts, Folders, and Note Inventory

### Goal

List Apple Notes accounts, folder trees, and note metadata without exporting anything.

This stage proves that the app can locate an account such as `iCloud`, resolve a configured folder path such as `myICOR Capture`, and list notes under it.

### Implementation tasks

- Add models for account, folder, and note metadata.
- Read accounts from the Notes metadata tables.
- Read folders from the Notes metadata tables.
- Read note metadata including UUID, title, snippet, folder, creation date, and modification date.
- Convert Core Data timestamps to normal dates.
- Add account listing command.
- Add folder listing command.
- Add note listing command.
- Avoid reading/decompressing full note bodies in this stage.

Suggested commands:

```bash
notes2myicor accounts
notes2myicor folders --account "iCloud"
notes2myicor notes --account "iCloud" --folder "myICOR Capture" --recursive
```

### Unit tests

- Core Data timestamp conversion is correct.
- Account records are mapped correctly from fixture rows.
- Folder records are mapped correctly from fixture rows.
- Note metadata records are mapped correctly from fixture rows.
- Null or missing optional fields are handled safely.
- Date formatting is stable.

### Integration/manual tests

- Run account listing against a fixture DB.
- Run folder listing against a fixture DB with nested folders.
- Run note listing against a fixture DB.
- Run all three commands against the real Apple Notes database.
- Confirm output includes UUIDs, titles, folder paths, and modified dates.

### Acceptance criteria

- The app can show available accounts.
- The app can show folder trees under an account.
- The app can list notes under a chosen folder.
- No PDFs are generated yet.

---

## Stage 3: Folder Scoping and Duplicate-Safe Resolution

### Goal

Implement robust folder scoping using account plus folder path, not folder name alone.

This is important because Apple Notes can have duplicate folder names in different accounts or parent folders.

### Implementation tasks

- Build an in-memory folder tree.
- Resolve account name to account ID/UUID.
- Resolve folder path to a specific root folder.
- Support recursive and non-recursive scope.
- Compute allowed folder IDs.
- Detect duplicate or ambiguous paths.
- Detect missing account.
- Detect missing folder path.
- Add diagnostics that explain which folder IDs are in scope.

Suggested command:

```bash
notes2myicor resolve-scope --account "iCloud" --folder "myICOR Capture" --recursive
```

### Unit tests

- Resolves a simple root folder.
- Resolves nested folder paths.
- Handles duplicate folder names under different parents.
- Handles duplicate folder names under different accounts.
- Recursive scope includes descendants.
- Non-recursive scope includes only the root folder.
- Missing account produces a clear error.
- Missing folder path produces a clear error.
- Ambiguous folder path produces a clear error if the schema cannot disambiguate safely.

### Integration/manual tests

- Run scope resolution against fixture data with duplicate names.
- Run scope resolution against the real Apple Notes account and target folder.
- Run note listing using the resolved folder ID set.

### Acceptance criteria

- Folder scoping is based on account and path.
- Recursive folder selection works.
- Duplicate names do not cause accidental exports from the wrong folder.

---

## Stage 4: Local State Database and Migrations

### Goal

Create the app-owned SQLite state database used to remember exported notes, scan runs, output paths, content hashes, failures, and deletion state.

This database is separate from Apple Notes and is safe for the app to write.

### Implementation tasks

- Add state DB path from config.
- Create state DB if missing.
- Add schema migration mechanism.
- Add `notes_state` table.
- Add `scan_runs` table.
- Add `sync_roots` table.
- Add state read/write APIs.
- Add status command.
- Add reset command for development.

Suggested commands:

```bash
notes2myicor status
notes2myicor reset-state --note-uuid <uuid>
```

### Unit tests

- State DB is created from scratch.
- Migrations are idempotent.
- Current schema version is stored and read correctly.
- Note state insert works.
- Note state update works.
- Scan run insert/update works.
- Sync root insert/update works.
- Resetting one note state works.
- Invalid state DB path reports a clear error.

### Integration/manual tests

- Create a state DB in a temporary directory.
- Run migrations twice and confirm no duplicate or broken schema.
- Run `status` against an empty state DB.
- Run `status` after inserting fixture note state.

### Acceptance criteria

- The app has its own durable state DB.
- State migrations are repeatable.
- No Apple Notes data is modified.

---

## Stage 5: Change Classification

### Goal

Compare the current Apple Notes inventory with the local state DB and classify notes as new, modified, metadata-changed, unchanged, out of scope, or missing.

This stage still does not export PDFs.

### Implementation tasks

- Add change classifier.
- Classify `NEW`.
- Classify `MODIFIED` based on modification timestamp.
- Classify `METADATA_CHANGED` based on title/folder/path changes.
- Classify `UNCHANGED`.
- Classify `OUT_OF_SCOPE` when a known note still exists but outside the configured folder tree.
- Classify `MISSING_POSSIBLY_DELETED` when a known note disappears from full inventory.
- Add missing scan grace count.
- Add scan summary output.

Suggested command:

```bash
notes2myicor scan --account "iCloud" --folder "myICOR Capture" --recursive
```

### Unit tests

- Unknown in-scope note becomes `NEW`.
- Known note with newer modification date becomes `MODIFIED`.
- Known note with same content metadata becomes `UNCHANGED`.
- Known note with renamed title becomes `METADATA_CHANGED`.
- Known note moved outside allowed folders becomes `OUT_OF_SCOPE`.
- Known note missing from full inventory increments missing count.
- Missing note below grace threshold is not marked deleted.
- Missing note at grace threshold becomes deletion candidate.
- Failed export state can be retried.

### Integration/manual tests

- Run scan against fixture inventory and fixture state DB.
- Run scan twice and confirm second scan does not classify everything as new.
- Move a fixture note out of scope and confirm classification.
- Remove a fixture note and confirm missing grace behavior.

### Acceptance criteria

- The app can tell what needs export without parsing note bodies.
- Repeated scans are stable.
- Missing and moved notes are handled conservatively.

---

## Stage 6: Snapshot Strategy

### Goal

Create a safe work snapshot of the Apple Notes data before full parsing/export.

This reduces risk from iCloud sync races, SQLite WAL behavior, and media files changing while export is running.

### Implementation tasks

- Add work directory from config.
- Add snapshot creation API.
- Choose initial snapshot method.
- Include `NoteStore.sqlite`, `NoteStore.sqlite-wal`, and `NoteStore.sqlite-shm` when present.
- Include relevant media/preview/fallback folders.
- Add snapshot cleanup policy.
- Add snapshot diagnostics.
- Ensure snapshots never write into the Apple Notes container.

Suggested command:

```bash
notes2myicor snapshot
```

### Unit tests

- Snapshot destination path is generated safely.
- Snapshot copies expected SQLite files when present.
- Snapshot handles missing WAL/SHM files.
- Snapshot handles missing media folders.
- Snapshot cleanup removes old work snapshots only.
- Snapshot never targets the live Apple Notes directory.

### Integration/manual tests

- Snapshot a fixture Notes container.
- Verify copied file list.
- Snapshot the real Notes container.
- Confirm the real Notes container is unchanged.
- Confirm snapshot can be opened by SQLite.

### Acceptance criteria

- A parser can run against a stable copied Notes container.
- WAL-related files are considered.
- Snapshotting is safe and local.

---

## Stage 7: Apple Cloud Notes Parser Integration

### Goal

Use Apple Cloud Notes Parser as the first extraction engine so the project can produce useful exports before a native Swift parser exists.

This is the recommended MVP parser path.

### Implementation tasks

- Add parser mode config.
- Add Apple Cloud Notes Parser executable path config.
- Add subprocess runner.
- Run parser against a snapshot using `--mac`.
- Request individual files, UUID filenames, retained display order, and JSON output.
- Parse Apple Cloud Notes Parser JSON.
- Locate parser-generated HTML and assets for requested note UUIDs.
- Normalize parser output into an internal representation or export package.
- Capture parser warnings/errors.
- Make one note failure non-fatal where possible.

Suggested command:

```bash
notes2myicor parse --note-uuid <uuid>
```

### Unit tests

- Parser command arguments are built correctly.
- Parser path validation works.
- Subprocess success is handled.
- Subprocess non-zero exit is handled.
- Parser JSON fixture is decoded correctly.
- Parser output is matched by UUID.
- Missing HTML for a note reports a clear error.
- Parser warnings are preserved.

### Integration/manual tests

- Run against a small fixture parser output directory.
- Run against Apple Cloud Notes Parser installed locally.
- Run against a snapshot of the real Apple Notes container.
- Confirm parsed UUIDs match metadata inventory UUIDs.

### Acceptance criteria

- The app can invoke Apple Cloud Notes Parser.
- The app can identify generated HTML/assets for changed notes.
- Parser failure does not corrupt app state.

---

## Stage 8: Intermediate Note Model and HTML Handling

### Goal

Represent extracted notes in an internal app model and prepare HTML suitable for PDF rendering.

For the MVP, this model may wrap Apple Cloud Notes Parser output rather than fully decode protobufs natively.

### Implementation tasks

- Add `NoteDocument` or `ParsedNote` model.
- Include UUID, title, account, folder path, dates, HTML path/content, assets, warnings.
- Add HTML sanitization or normalization where needed.
- Add app metadata header option.
- Add debug HTML output option.
- Ensure relative asset paths resolve during PDF rendering.
- Add content hashing inputs.

### Unit tests

- Parsed note model serializes to JSON.
- HTML metadata header is generated correctly.
- HTML escaping works for titles/folder names.
- Asset paths are resolved correctly.
- Content hash changes when body changes.
- Content hash changes when embedded object list changes.
- Content hash remains stable for irrelevant path differences.

### Integration/manual tests

- Generate debug HTML for fixture parser output.
- Open debug HTML locally and confirm assets load.
- Compare generated model JSON with source parser JSON.

### Acceptance criteria

- The app has a stable internal representation for exported notes.
- HTML is ready for rendering.
- Content hashing is available before writing PDFs.

---

## Stage 9: PDF Rendering, Output Writing, and Sidecar JSON

### Goal

Render note HTML to PDF, write it to the configured output directory, and write sidecar JSON metadata.

### Implementation tasks

- Add PDF renderer using `WKWebView.createPDF` or another chosen renderer.
- Add PDF write API.
- Add output naming strategy.
- Add safe filename sanitizer.
- Add output directory creation.
- Add sidecar JSON writer.
- Add optional debug HTML writer.
- Add PDF metadata where practical.
- Add failure output folder handling.

Suggested command:

```bash
notes2myicor export --note-uuid <uuid>
```

### Unit tests

- Filename sanitizer removes unsafe characters.
- Long filenames are truncated safely.
- UUID-title filename strategy is stable.
- Output path mirrors folder tree when configured.
- Sidecar JSON contains required fields.
- Existing PDF replacement is atomic where practical.
- Output writer handles unwritable directories.

### Integration/manual tests

- Render a simple HTML fixture to PDF.
- Render HTML with images to PDF.
- Verify the generated PDF exists and is non-empty.
- Verify sidecar JSON exists and is valid JSON.
- Verify debug HTML exists when enabled.
- Open the PDF manually and confirm layout is readable.

### Acceptance criteria

- A parsed note can become a PDF.
- PDF and sidecar files are written to the configured output directory.
- Output filenames are readable and stable.

---

## Stage 10: Full `sync --once` MVP

### Goal

Connect inventory, scope resolution, change classification, snapshotting, parsing, PDF rendering, output writing, and state updates into one command.

This is the first true MVP.

### Implementation tasks

- Implement `sync --once`.
- Begin and finish scan run records.
- Export only `NEW` and `MODIFIED` notes.
- Handle `METADATA_CHANGED` according to configured rename/update policy.
- Compute content hash before deciding whether to rewrite PDF.
- Mark export success only after PDF and sidecar write succeed.
- Mark export failure per note and continue.
- Produce useful scan summary.
- Add dry-run mode.

Suggested commands:

```bash
notes2myicor sync --once
notes2myicor sync --once --dry-run
```

### Unit tests

- Sync engine exports new notes.
- Sync engine exports modified notes.
- Sync engine skips unchanged notes.
- Sync engine does not mark success if parsing fails.
- Sync engine does not mark success if PDF writing fails.
- Per-note failure does not stop later notes.
- Content hash prevents unnecessary rewrite.
- Scan run summary counts are correct.

### Integration/manual tests

- Run full sync against fixture Notes data and fake parser output.
- Run full sync twice and confirm second run skips unchanged notes.
- Modify fixture note metadata and confirm reclassification.
- Run dry-run and confirm no files are written.
- Run against real Apple Notes test folder with at least one simple note.

### Acceptance criteria

- One command can export changed notes to PDF.
- State is updated correctly.
- Re-running sync does not export everything again.
- Failures are isolated to individual notes.

---

## Stage 11: Deletion, Recently Deleted, and Out-of-Scope Handling

### Goal

Handle notes that disappear, move out of scope, or appear in Recently Deleted without destroying exported PDFs.

### Implementation tasks

- Add deletion policy implementation.
- Track `missing_scan_count`.
- Track `first_missing_at`.
- Mark hard deletion only after grace threshold.
- Detect out-of-scope notes that still exist elsewhere.
- Detect Recently Deleted when possible.
- Add `_OutOfScope` handling if move/archive policy is explicitly enabled later.
- Add `_Deleted/Recently Deleted` handling if move/archive policy is explicitly enabled later.
- Add `_Deleted/Permanently Missing` handling if move/archive policy is explicitly enabled later.
- Make move-vs-mark behavior configurable.
  - Current default for this project is mark-only: update state, preserve exported files in place.

### Unit tests

- One missing scan does not mark deleted.
- Missing below threshold preserves active PDF.
- Missing at threshold marks deleted.
- Deleted note PDF is preserved by the default mark-only policy.
- Out-of-scope note is not marked deleted.
- Out-of-scope PDF handling preserves files by default.
- Recently Deleted note is marked soft-deleted when detectable.
- Deletion policy is idempotent.

### Integration/manual tests

- Export a fixture note, then remove it from inventory for multiple scans.
- Export a fixture note, then move it outside the allowed folder.
- Confirm PDFs are preserved.
- Confirm state DB reflects deleted/out-of-scope status.
- Manually test with a real Apple Notes test note moved out of folder.
- Manually test with a real Apple Notes test note deleted into Recently Deleted.

### Acceptance criteria

- The app never permanently deletes exported PDFs automatically.
- Moved notes are not confused with deleted notes.
- Missing notes require repeated confirmation before deletion state.

---

## Stage 12: LaunchAgent and Watch Mode

### Goal

Allow the sync to run automatically on a schedule.

### Implementation tasks

- Add `sync --watch` polling loop if useful.
- Add LaunchAgent plist generator.
- Add LaunchAgent install command.
- Add LaunchAgent uninstall command.
- Add LaunchAgent status command where practical.
- Add configurable polling interval.
- Add log file paths.
- Avoid overlapping sync runs.

Suggested commands:

```bash
notes2myicor install-launch-agent
notes2myicor uninstall-launch-agent
notes2myicor sync --watch
```

### Unit tests

- LaunchAgent plist contains expected label.
- LaunchAgent plist contains expected program arguments.
- Poll interval is written correctly.
- Log paths are written correctly.
- Plist generation is deterministic.
- Install refuses unsafe binary paths.

### Integration/manual tests

- Generate plist into a temporary directory.
- Validate plist with `plutil`.
- Install LaunchAgent manually in a test environment.
- Confirm scheduled sync writes logs.
- Confirm uninstall removes/unloads the LaunchAgent.

### Acceptance criteria

- The app can be scheduled to run every few minutes.
- Logs are discoverable.
- Manual sync remains available.

---

## Stage 13: Real Apple Notes Test Corpus

### Goal

Create and document a controlled real-world Apple Notes folder used for acceptance testing.

This stage is partly manual because it depends on creating representative notes on an iPad.

### Implementation tasks

- Create test folder, for example `myICOR Capture Test`.
- Add documented test notes.
- Add acceptance checklist.
- Capture expected behavior for each note.
- Compare app output with Apple Cloud Notes Parser output.
- Record known limitations.

Recommended test notes:

- Plain text.
- Rich text.
- Headings.
- Bulleted list.
- Numbered list.
- Checklist.
- Link.
- Table.
- Image.
- Apple Pencil handwriting.
- Apple Pencil sketch/diagram.
- Scanned document.
- PDF attachment.
- Long multi-page note.
- Note in subfolder.
- Note renamed after export.
- Note modified after export.
- Note moved into scope.
- Note moved out of scope.
- Note deleted.

### Unit tests

- No new unit tests are required solely for manual corpus creation.
- Any defects discovered from the corpus should become fixture-based regression tests in the relevant module.

### Integration/manual tests

- Create each test note on iPad.
- Wait for iCloud sync to Mac.
- Run `notes2myicor sync --once`.
- Confirm each expected PDF appears.
- Open each PDF and verify readability.
- Confirm sidecar JSON metadata.
- Modify selected notes and confirm re-export.
- Move selected notes and confirm out-of-scope handling.
- Delete selected notes and confirm conservative deletion behavior.

### Acceptance criteria

- The MVP works against real Apple Notes data.
- Known unsupported features are documented.
- Regression fixtures exist for bugs found during corpus testing.

---

## Stage 14: Native Swift Parser Proof of Concept

### Goal

Begin replacing Apple Cloud Notes Parser for simple notes by decoding `ZICNOTEDATA.ZDATA` natively in Swift.

This is not required for the MVP, but it is the path toward a self-contained app.

### Implementation tasks

- Locate note body data from `ZICNOTEDATA.ZDATA`.
- Decompress gzipped note payloads.
- Add protobuf definitions or generated Swift types.
- Decode simple text notes.
- Convert decoded data into internal `NoteDocument`.
- Compare native output with Apple Cloud Notes Parser output.
- Add parser mode switch: `apple-cloud-notes-parser` vs `native-swift`.

### Unit tests

- Gzip decompression works for fixture payloads.
- Invalid gzip data produces a clear error.
- Simple protobuf fixture decodes correctly.
- Simple text note model matches expected output.
- Unsupported fields produce warnings, not crashes.
- Parser mode selection works.

### Integration/manual tests

- Run native parser against simple fixture notes.
- Compare UUID, title, plaintext, and HTML against Apple Cloud Notes Parser.
- Run native parser against one real simple note.
- Fall back or report unsupported for complex notes.

### Acceptance criteria

- Simple text notes can be parsed without Apple Cloud Notes Parser.
- Complex notes remain safely handled by the existing parser path or clear unsupported warnings.

---

## Stage 15: Embedded Object Support

### Goal

Improve support for images, sketches, scans, PDFs, tables, and other embedded Apple Notes objects.

This stage should be driven by the real test corpus and actual myICOR needs.

### Implementation tasks

- Add image extraction support.
- Add Apple Pencil drawing/sketch support where possible.
- Add table support.
- Add embedded PDF support.
- Add scanned document support.
- Add attachment extraction warnings.
- Add PDF append/separate/link-only modes for embedded PDFs.
- Add visual regression samples.

### Unit tests

- Image object maps to expected model.
- Missing image file produces a warning.
- Table maps to expected model.
- Embedded PDF metadata maps to expected model.
- PDF append/separate mode config is respected.
- Unsupported embedded object produces a warning.

### Integration/manual tests

- Export test notes with images.
- Export test notes with handwriting/sketches.
- Export test notes with scans.
- Export test notes with embedded PDFs.
- Confirm multi-page embedded PDFs are preserved where possible.
- Compare output with Apple Notes manual PDF export and Apple Cloud Notes Parser output.

### Acceptance criteria

- The features used in the real iPad workflow are exported well enough for myICOR ingestion.
- Unsupported embedded objects are visible in warnings.
- The app does not silently drop important attachments.

---

## Stage 16: Packaging, Privacy, and Release Readiness

### Goal

Make the tool usable outside a development checkout.

### Implementation tasks

- Add install instructions.
- Add build/release script.
- Add binary install location recommendation.
- Add Full Disk Access instructions.
- Add privacy statement.
- Add third-party notices for Apple Cloud Notes Parser if used.
- Add troubleshooting guide.
- Add example config.
- Add upgrade/migration notes.
- Add release checklist.

### Unit tests

- Example config parses successfully.
- Third-party notice file exists when parser integration is enabled.
- Release metadata contains required fields.

### Integration/manual tests

- Build release binary.
- Install binary to expected location.
- Run `notes2myicor --help` from installed location.
- Run `notes2myicor sync --once` from installed location.
- Confirm LaunchAgent uses installed binary.

### Acceptance criteria

- The project can be installed and run by following documentation.
- Privacy and licensing obligations are documented.
- The tool is ready for regular personal use.

---

## Suggested Order of Completion

The recommended order is:

```text
Stage 0  Project bootstrap
Stage 1  Apple Notes schema discovery
Stage 2  Accounts/folders/notes inventory
Stage 3  Folder scoping
Stage 4  State database
Stage 5  Change classification
Stage 6  Snapshot strategy
Stage 7  Apple Cloud Notes Parser integration
Stage 8  Intermediate note model and HTML
Stage 9  PDF rendering and sidecars
Stage 10 Full sync MVP
Stage 11 Deletion and out-of-scope handling
Stage 12 LaunchAgent/watch mode
Stage 13 Real Apple Notes test corpus
Stage 14 Native Swift parser proof of concept
Stage 15 Embedded object support
Stage 16 Packaging and release readiness
```

Stages 0 through 10 form the practical MVP path.

Stages 11 through 13 make the MVP safer and more trustworthy for daily use.

Stages 14 and 15 reduce reliance on Apple Cloud Notes Parser and improve fidelity.

Stage 16 makes the project maintainable as a real personal utility.

---

## Definition of Done for Every Stage

Every implementation stage should finish with:

- Code committed or at least cleanly separated in the working tree.
- `swift test` passing.
- Relevant CLI command manually exercised.
- Any new config documented.
- Any known limitation added to docs or issue notes.
- No accidental writes to the Apple Notes container.
- No deletion of exported PDFs unless explicitly part of a safe move/archive policy.

For stages that touch real Apple Notes data, the stage is not complete until the command has been run successfully against both:

- controlled fixture data, and
- the real local Apple Notes database, where permissions allow.
