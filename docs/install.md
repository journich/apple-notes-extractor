# Install Notes2MyICOR

`notes2myicor` is currently a Swift command-line tool for personal macOS use.

## Prerequisites

- macOS with locally synced Apple Notes.
- Full Xcode selected with `xcode-select`, not Command Line Tools only.
- Swift 6.3 or newer from Xcode.
- Homebrew Ruby when using Apple Cloud Notes Parser.
- Apple Cloud Notes Parser cloned outside this repository when using the default MVP parser mode.

Verify Swift:

```bash
xcode-select -p
xcrun --find swift
swift --version
```

## Build And Install

Recommended personal install location:

```text
~/bin/notes2myicor
```

Build and install:

```bash
./scripts/build-release.sh "$HOME/bin"
```

Verify the installed binary:

```bash
"$HOME/bin/notes2myicor" --help
"$HOME/bin/notes2myicor" version
```

If `~/bin` is not on `PATH`, add it in your shell profile:

```bash
export PATH="$HOME/bin:$PATH"
```

## Full Disk Access

macOS may block access to Apple Notes' local container until the calling app has permission.

Open System Settings:

```text
Privacy & Security -> Full Disk Access
```

Add the app that launches `notes2myicor`:

- Terminal, iTerm2, or the shell host used for manual runs.
- The installed `notes2myicor` binary if macOS prompts for it.
- The automation host if running through a scheduler.

After changing permissions, restart the terminal or automation host before testing again.

## First Run

Create a local config file:

```bash
notes2myicor init
```

List accounts and folders without reading note bodies:

```bash
notes2myicor accounts
notes2myicor folders --account "iCloud"
```

Run a dry run against all folders:

```bash
notes2myicor sync --once --dry-run --account "iCloud" --folder /
```

Run a real export to a temporary directory first:

```bash
notes2myicor sync --once --account "iCloud" --folder / --parser-script /path/to/notes_cloud_ripper.rb --output-dir /tmp/notes2myicor-export
```

Real export output contains note contents. Keep it outside the repository.

## LaunchAgent

Install the LaunchAgent plist with the installed binary path:

```bash
notes2myicor install-launch-agent --binary "$HOME/bin/notes2myicor" --interval-seconds 300 --account "iCloud" --folder /
notes2myicor launch-agent-status
```

The install command writes the plist only. Load or unload it with `launchctl` when ready.
