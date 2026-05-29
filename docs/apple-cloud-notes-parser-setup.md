# Apple Cloud Notes Parser Setup Notes

Stage 7 integrates Apple Cloud Notes Parser as the first extraction engine.

## Current Local Setup

Apple Cloud Notes Parser has been cloned as a sibling directory of this repository:

```text
../apple_cloud_notes_parser
```

The expected parser script is:

```text
../apple_cloud_notes_parser/notes_cloud_ripper.rb
```
Do not commit the parser repository into this repository.

## Current Blocker

Running `bundle install` with the macOS system Ruby failed because the active Ruby is too old for the resolved `google-protobuf` dependency.

Observed active Ruby:

```text
ruby 2.6.10
```

Observed dependency problem:

```text
google-protobuf >= 4.26 depends on ruby >= 2.7
```

This means Stage 7 needs a newer Ruby runtime before Apple Cloud Notes Parser can be used reliably.

## Recommended Fix

Install a modern Ruby with Homebrew, rbenv, asdf, or another Ruby version manager, then rerun Bundler inside the parser repository.

Example with Homebrew Ruby:

```bash
brew install ruby
cd ../apple_cloud_notes_parser
/opt/homebrew/opt/ruby/bin/gem install bundler
/opt/homebrew/opt/ruby/bin/ruby -S bundle install
```

After setup, verify:

```bash
cd ../apple_cloud_notes_parser
/opt/homebrew/opt/ruby/bin/ruby --version
/opt/homebrew/opt/ruby/bin/gem install logger
/opt/homebrew/opt/ruby/bin/ruby notes_cloud_ripper.rb --help
```

Use the explicit Homebrew Ruby path. On macOS, plain `ruby`, `gem`, and `bundle` may still resolve to the system Ruby 2.6 even after Homebrew Ruby is installed.

Once this works, Stage 7 can continue by configuring `notes2myicor` to call:

```text
../apple_cloud_notes_parser/notes_cloud_ripper.rb
```

Stage 8 can generate renderable debug HTML from parser output:

```bash
swift run notes2myicor parse --parser-script ../apple_cloud_notes_parser/notes_cloud_ripper.rb --debug-html-dir /tmp/notes2myicor-debug-html
```

Debug HTML is generated output and may contain note contents. Keep it outside the repository and delete it after local verification.
