# apple-notes-extractor

`apple-notes-extractor` is the working repository for `notes2myicor`, a macOS utility that will export locally synced Apple Notes to PDFs for folder-based knowledge workflows.

The project is intentionally CLI-first. The first implementation stages establish a tested Swift package before any Apple Notes data is read.

## Build

```bash
swift build
```

## Test

```bash
swift test
```

## Run

```bash
swift run notes2myicor --help
swift run notes2myicor version
swift run notes2myicor init
swift run notes2myicor inspect-schema
swift run notes2myicor accounts
swift run notes2myicor folders --account "iCloud"
swift run notes2myicor notes --account "iCloud" --folder "Capture" --recursive
swift run notes2myicor resolve-scope --account "iCloud" --folder "Capture" --recursive
swift run notes2myicor status
```

`notes2myicor init` creates a default JSON config at:

```text
~/Library/Application Support/Notes2MyICOR/config.json
```

The generated config is local runtime state and is ignored by Git.

## Implemented Stages

Stage 0 is the bootstrap stage:

- Swift package
- CLI entrypoint
- core library target
- basic config model and JSON config store
- path expansion helpers
- structured JSON-line logger
- tests for the baseline behavior

No Apple Notes data is read during Stage 0.

Stage 1 adds read-only schema inspection for the local Apple Notes SQLite store:

```bash
swift run notes2myicor inspect-schema
```

For fixture or development databases:

```bash
swift run notes2myicor inspect-schema --database /path/to/NoteStore.sqlite
```

The command opens SQLite in read-only URI mode, sets `PRAGMA query_only = ON`, and prints table/column metadata only. It does not read or print note bodies.

Stage 2 adds metadata inventory commands:

```bash
swift run notes2myicor accounts
swift run notes2myicor folders --account "iCloud"
swift run notes2myicor notes --account "iCloud" --folder "Capture" --recursive
```

These commands read account, folder, and note metadata only. They do not decompress or parse note bodies.

Stage 3 adds duplicate-safe folder scope resolution:

```bash
swift run notes2myicor resolve-scope --account "iCloud" --folder "Capture" --recursive
```

The resolver uses account name plus full folder path, then returns the root folder and allowed descendant folder IDs.

Stage 4 adds the app-owned state database:

```bash
swift run notes2myicor status
swift run notes2myicor reset-state --note-uuid <uuid>
```

The state database is separate from Apple Notes and is safe for this app to create and update.
