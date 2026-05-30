# Privacy

Treat every committed file in this repository as public.

`notes2myicor` is designed to run locally:

- It reads the local Apple Notes SQLite store read-only.
- It sets SQLite read-only/query-only protections where applicable.
- It writes app-owned state, PDFs, sidecar JSON, logs, and snapshots outside the repository.
- It does not authenticate to iCloud.
- It does not call Apple cloud APIs.
- It does not write to Apple Notes databases or media folders.
- It does not send note contents to external services.

The default MVP parser path runs Apple Cloud Notes Parser locally as a subprocess when configured. That parser is installed separately and should be reviewed before use.

Never commit:

- Apple Notes databases or snapshots.
- Apple Notes media folders.
- Exported PDFs.
- Sidecar JSON generated from real notes.
- Parser output generated from real notes.
- State databases.
- Logs containing note titles, snippets, body text, paths, or errors from real data.
- Local config files containing personal paths.
- Authentication tokens, keys, passwords, certificates, cookies, or other secrets.

Use `/tmp` or another ignored local directory for manual test output.
