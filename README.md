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
swift run notes2myicor scan --account "iCloud" --folder "Capture" --recursive
swift run notes2myicor snapshot
swift run notes2myicor parse --parser-script ../apple_cloud_notes_parser/notes_cloud_ripper.rb
swift run notes2myicor parse --parser-mode native-swift --note-uuid <uuid>
swift run notes2myicor parse --parser-script ../apple_cloud_notes_parser/notes_cloud_ripper.rb --debug-html-dir /tmp/notes2myicor-debug-html
swift run notes2myicor export --note-uuid <uuid> --parser-script ../apple_cloud_notes_parser/notes_cloud_ripper.rb --output-dir /tmp/notes2myicor-export
swift run notes2myicor sync --once --account "iCloud" --folder "Capture" --recursive --parser-script ../apple_cloud_notes_parser/notes_cloud_ripper.rb --output-dir /tmp/notes2myicor-export
swift run notes2myicor sync --once --dry-run --account "iCloud" --folder "Capture" --recursive
swift run notes2myicor sync --once --dry-run --account "iCloud" --folder /
swift run notes2myicor sync --watch --interval-seconds 300 --account "iCloud" --folder "Capture" --recursive
swift run notes2myicor install-launch-agent --binary /path/to/notes2myicor --interval-seconds 300 --account "iCloud" --folder "Capture" --recursive
swift run notes2myicor launch-agent-status
swift run notes2myicor uninstall-launch-agent
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
swift run notes2myicor resolve-scope --account "iCloud" --folder /
```

The resolver uses account name plus full folder path, then returns the root folder and allowed descendant folder IDs.
Use `--folder /` to select every folder in the account.

Stage 4 adds the app-owned state database:

```bash
swift run notes2myicor status
swift run notes2myicor reset-state --note-uuid <uuid>
```

The state database is separate from Apple Notes and is safe for this app to create and update.

Stage 5 adds metadata-only change classification:

```bash
swift run notes2myicor scan --account "iCloud" --folder "Capture" --recursive
```

The scan command classifies notes as new, modified, unchanged, out of scope, missing, or previously failed. It does not parse note bodies and does not export PDFs.

Stage 6 adds snapshot creation:

```bash
swift run notes2myicor snapshot
```

Snapshots copy `NoteStore.sqlite`, WAL/SHM files when present, and known asset folders into the configured work directory. They never write into the live Apple Notes container.

Stage 7 adds Apple Cloud Notes Parser integration:

```bash
swift run notes2myicor parse --parser-script ../apple_cloud_notes_parser/notes_cloud_ripper.rb
```

By default the parser is run with Homebrew Ruby at `/opt/homebrew/opt/ruby/bin/ruby`, and its JSON output is decoded from `notes_rip/json/all_notes_1.json`.

Stage 8 adds the internal `NoteDocument` model used by later PDF export stages. Parser output is normalized into note documents with metadata slots, asset references, warnings, renderable HTML, and SHA-256 content hashes.

To write renderable debug HTML while testing parser output, provide a temporary output directory:

```bash
swift run notes2myicor parse --parser-script ../apple_cloud_notes_parser/notes_cloud_ripper.rb --debug-html-dir /tmp/notes2myicor-debug-html
```

Debug HTML may contain note contents. Keep debug output local and untracked.

Stage 9 adds HTML-to-PDF export using WebKit. This raises the package minimum to macOS 11 because `WKWebView.createPDF` is the native PDF rendering path.

For a parser-backed note export:

```bash
swift run notes2myicor export --note-uuid <uuid> --parser-script ../apple_cloud_notes_parser/notes_cloud_ripper.rb --output-dir /tmp/notes2myicor-export
```

For a synthetic or debug HTML fixture:

```bash
swift run notes2myicor export --note-uuid fixture-uuid --title "Fixture" --html /tmp/fixture.html --output-dir /tmp/notes2myicor-export --debug-html
```

Exports write a PDF and sidecar JSON. `--debug-html` also writes the rendered HTML next to the PDF. Output files may contain note contents; keep test output local and untracked.

Stage 10 adds the first full MVP sync command:

```bash
swift run notes2myicor sync --once --account "iCloud" --folder "Capture" --recursive --parser-script ../apple_cloud_notes_parser/notes_cloud_ripper.rb --output-dir /tmp/notes2myicor-export
swift run notes2myicor sync --once --dry-run --account "iCloud" --folder "Capture" --recursive
```

`sync --once` reads the Notes inventory, classifies changes, parses changed notes, writes PDFs and sidecar JSON, and updates the app-owned state database only after successful export. `--dry-run` reports planned work without parsing, exporting, or updating note state. Current sync state stores Apple Notes folder object IDs for change comparison; sidecar JSON and exported documents still use human folder paths.

Stage 11 adds conservative deletion and out-of-scope handling. The default policy is mark-only:

- notes missing below the grace threshold keep their PDF path and are not marked deleted;
- notes missing at the grace threshold are marked deleted in state, but their PDFs are not moved or removed;
- notes moved outside the selected folder are marked out of scope, not deleted;
- notes detected in a `Recently Deleted` folder are marked soft-deleted in state;
- exported PDFs and sidecar JSON are preserved in place.

Stage 12 adds scheduled operation support:

```bash
swift run notes2myicor sync --watch --interval-seconds 300 --account "iCloud" --folder "Capture" --recursive
swift run notes2myicor install-launch-agent --binary /path/to/notes2myicor --interval-seconds 300 --account "iCloud" --folder "Capture" --recursive
swift run notes2myicor launch-agent-status
swift run notes2myicor uninstall-launch-agent
```

`sync --watch` runs `sync --once` serially and sleeps between runs, so it does not start a new sync while a previous sync is still running. `install-launch-agent` writes a LaunchAgent plist, defaulting to `~/Library/LaunchAgents/com.journich.notes2myicor.plist`, with logs under `~/Library/Logs/Notes2MyICOR`. Use `--binary` with an installed absolute executable path; relative, missing, non-executable, or directory paths are refused. The command writes the plist only; load or unload it with `launchctl` when you are ready to enable or disable scheduled background execution in your macOS session.

Stage 13 validates the MVP against real Apple Notes data using account-root scope:

```bash
swift run notes2myicor sync --once --dry-run --account "iCloud" --folder /
swift run notes2myicor sync --once --account "iCloud" --folder / --parser-script /path/to/notes_cloud_ripper.rb --output-dir /tmp/notes2myicor-export
```

Real export output contains private note content. Keep generated PDFs, sidecar JSON, parser output, state databases, logs, and snapshots local and untracked.

Stage 14 adds a native Swift parser proof of concept:

```bash
swift run notes2myicor parse --parser-mode native-swift --note-uuid <uuid>
swift run notes2myicor sync --once --parser-mode native-swift --account "iCloud" --folder / --output-dir /tmp/notes2myicor-native-export
```

The native parser currently handles simple gzipped `ZICNOTEDATA.ZDATA` payloads by decoding enough of the Apple Notes protobuf to extract plain note text. It intentionally ignores Apple Notes formatting attribute runs and embedded objects for now, reporting warnings instead of attempting partial rich rendering. Use the default `apple-cloud-notes-parser` mode for full MVP exports.
