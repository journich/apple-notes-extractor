# Troubleshooting

## `operation not permitted` Or Empty Notes Output

Grant Full Disk Access to the terminal or automation host running `notes2myicor`, then restart that app.

## `NoteStore.sqlite` Not Found

Confirm Apple Notes is enabled for the account and has synced locally. Then inspect the default container:

```bash
notes2myicor inspect-schema
```

Use `--notes-container <path>` only for fixtures or explicit diagnostics.

## Parser Script Not Found

Pass the Apple Cloud Notes Parser script explicitly:

```bash
notes2myicor parse --parser-script /path/to/notes_cloud_ripper.rb
```

Apple Cloud Notes Parser is not vendored in this repository.

## Ruby Or Bundler Problems

Use Homebrew Ruby when the system Ruby is too old for parser dependencies:

```bash
brew install ruby
/opt/homebrew/opt/ruby/bin/gem install bundler
```

Then pass the Ruby executable:

```bash
notes2myicor parse --ruby /opt/homebrew/opt/ruby/bin/ruby --parser-script /path/to/notes_cloud_ripper.rb
```

## LaunchAgent Does Not Run

Check that the plist points at an absolute installed binary path:

```bash
notes2myicor launch-agent-status
```

Check the configured log directory, usually:

```text
~/Library/Logs/Notes2MyICOR
```

If macOS permissions changed, unload and reload the LaunchAgent after restarting the host session.

## Embedded Objects Are Missing

Check the sidecar JSON `warnings` and `embedded_objects` fields. Unsupported Apple Notes object types are recorded there instead of being silently dropped.

## Real Export Output Appears In Git

Stop and do not commit. Remove the generated files from the working tree or move them outside the repository. Then run:

```bash
git status --short --ignored
```
