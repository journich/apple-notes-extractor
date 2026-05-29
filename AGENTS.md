# AGENTS.md

Guidance for AI coding agents working in this repository.

This repository is public on GitHub:

```text
https://github.com/journich/apple-notes-extractor
```

Treat every committed file as public.

## Project Purpose

This project is a macOS utility for exporting locally synced Apple Notes into PDFs for folder-based ingestion systems.

The intended workflow is:

```text
iPad Apple Notes
  -> iCloud sync handled by macOS
  -> local Mac utility reads Apple Notes data read-only
  -> changed notes are rendered to PDF
  -> PDFs and sidecar metadata are written to a configured output folder
```

The tool must not authenticate to iCloud, call Apple cloud APIs, edit Apple Notes, or write to Apple Notes' database or media folders.

## Repository Safety Rules

Before every commit and push, perform a public-repo safety check.

At minimum:

1. Review `git status --short --ignored`.
2. Review the exact tracked or staged files.
3. Scan staged/committed content for secrets and private data.
4. Confirm no Apple Notes databases, snapshots, PDFs, parser output, local configs, logs, tokens, or credentials are tracked.
5. Commit only after the safety check is clean.
6. Push only after the commit is known to be safe for a public repository.

Suggested scan command:

```bash
git grep -n -i -E '(password[[:space:]]*=|token[[:space:]]*=|secret[[:space:]]*=|apikey|api_key|gho_|github_pat|BEGIN [A-Z ]*PRIVATE KEY|/Users/[^ /]+)' HEAD -- . || true
```

Also scan staged content before committing:

```bash
git diff --cached --name-only
git diff --cached
```

Use judgment beyond these commands. The scan is a backstop, not a guarantee.

## Stage Completion Rule

The project is broken into stages in:

```text
docs/apple-notes-to-pdf-implementation-stages.md
```

At the end of each completed stage:

1. Run the relevant automated tests.
2. Run the relevant manual/integration command for that stage where practical.
3. Update documentation for new commands, config, limitations, or setup requirements.
4. Perform the public-repo safety check.
5. Commit the completed stage.
6. Push the commit to `origin/main`.

Do not push partial stage work unless the user explicitly asks for it.

## Data That Must Never Be Committed

Do not commit:

- Apple Notes SQLite databases, including `NoteStore.sqlite`, `NoteStore.sqlite-wal`, and `NoteStore.sqlite-shm`.
- Apple Notes media folders or snapshots.
- Exported PDFs.
- Sidecar JSON generated from real notes.
- Parser output generated from real notes.
- Local state databases.
- Logs containing note titles, snippets, body text, paths, or errors from real data.
- Local config files containing personal paths or account names.
- Authentication tokens, GitHub tokens, API keys, passwords, private keys, certificates, or cookies.
- `.DS_Store` or other operating system metadata.

Keep `.gitignore` updated as new generated paths are introduced.

## Apple Notes Handling Rules

The application must be read-only with respect to Apple Notes.

Allowed:

- Open the local Apple Notes SQLite database in read-only mode.
- Use `PRAGMA query_only = ON`.
- Copy the Apple Notes container into a work snapshot for parsing.
- Read copied snapshot files.

Forbidden:

- Write to Apple Notes' live database.
- Add columns, tables, indexes, triggers, or metadata to Apple Notes' database.
- Run SQLite checkpoint or vacuum operations against Apple Notes' database.
- Modify Apple Notes media, preview, fallback, or attachment folders.
- Delete Apple Notes data.
- Send Apple Notes content to external services.

If real Apple Notes data is needed for manual testing, keep it local and untracked.

## Implementation Preferences

Follow the staged plan unless the user explicitly changes direction.

Preferred initial architecture:

- Swift CLI first.
- Core logic in a reusable Swift library target.
- App-owned SQLite state database.
- Read-only Apple Notes metadata access.
- Apple Cloud Notes Parser integration for the first useful MVP parser path.
- Native Swift parser later, after the sync/export pipeline works.

Prefer small, testable modules:

- config and paths,
- Apple Notes schema inspection,
- account/folder/note inventory,
- folder scope resolution,
- state database,
- change classification,
- snapshot creation,
- parser integration,
- HTML/PDF rendering,
- output writing,
- deletion/out-of-scope policy.

## Testing Expectations

Every implementation stage should include tests appropriate to its risk.

Use unit tests for:

- config parsing,
- path expansion,
- timestamp conversion,
- folder path resolution,
- duplicate folder handling,
- change classification,
- state DB migrations,
- filename sanitization,
- sidecar JSON generation,
- deletion grace policy.

Use integration tests or fixture tests for:

- SQLite schema inspection,
- inventory loading,
- state DB behavior,
- parser output decoding,
- HTML-to-PDF rendering where practical.

Use manual tests for:

- real Apple Notes permission behavior,
- real account/folder discovery,
- real iCloud sync timing,
- actual PDF readability,
- LaunchAgent install/uninstall.

When a stage cannot be fully tested because it requires local Apple Notes data or permissions, clearly report what was and was not verified.

## Git and GitHub Rules

Use the `journich` GitHub account and push to:

```text
origin https://github.com/journich/apple-notes-extractor.git
```

Use public-safe commit authorship. Prefer GitHub no-reply email for commits:

```text
journich <70119791+journich@users.noreply.github.com>
```

Do not rewrite published history unless the user explicitly asks and the reason is clear, such as removing sensitive data.

## Documentation Expectations

Keep documentation current as the project evolves.

Update docs when adding:

- CLI commands,
- config options,
- generated file paths,
- setup steps,
- permissions requirements,
- parser limitations,
- known unsupported Apple Notes features,
- test corpus requirements.

Use generic examples in public docs. Do not include personal names, private folder names, local usernames, real note titles, real snippets, or personal filesystem paths.
