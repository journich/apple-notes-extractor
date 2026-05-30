# Release Checklist

Use this checklist before tagging or publishing a release.

## Build

- Run `swift test`.
- Run `swift build -c release`.
- Run `./scripts/build-release.sh "$HOME/bin"`.
- Run `"$HOME/bin/notes2myicor" --help`.
- Run `"$HOME/bin/notes2myicor" version`.

## Manual Smoke Test

- Run `notes2myicor accounts`.
- Run `notes2myicor folders --account "iCloud"`.
- Run `notes2myicor sync --once --dry-run --account "iCloud" --folder /`.
- Run one real export to a temporary output directory.
- Confirm PDFs open.
- Confirm sidecar JSON exists and contains `embedded_objects`.
- Confirm LaunchAgent plist generation uses the installed binary path.

## Privacy

- Run `git status --short --ignored`.
- Review staged files with `git diff --cached --name-only`.
- Review staged content with `git diff --cached`.
- Confirm no Apple Notes databases, snapshots, PDFs, sidecar JSON, parser output, logs, local configs, state databases, tokens, or credentials are staged.
- Run the repository safety scan from `AGENTS.md`.

## Documentation

- Confirm `README.md` references the current stage behavior.
- Confirm `docs/install.md` is current.
- Confirm `docs/privacy.md` is current.
- Confirm `docs/troubleshooting.md` is current.
- Confirm `THIRD_PARTY_NOTICES.md` is current.
- Confirm `release-metadata.json` has the intended version and minimum macOS version.
