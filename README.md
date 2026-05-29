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
```

`notes2myicor init` creates a default JSON config at:

```text
~/Library/Application Support/Notes2MyICOR/config.json
```

The generated config is local runtime state and is ignored by Git.

## Current Stage

Stage 0 is the bootstrap stage:

- Swift package
- CLI entrypoint
- core library target
- basic config model and JSON config store
- path expansion helpers
- structured JSON-line logger
- tests for the baseline behavior

No Apple Notes data is read during Stage 0.
