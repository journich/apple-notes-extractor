#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
install_dir="${1:-$HOME/bin}"
binary_name="notes2myicor"

cd "$repo_root"

swift build -c release
mkdir -p "$install_dir"
cp ".build/release/$binary_name" "$install_dir/$binary_name"
chmod 755 "$install_dir/$binary_name"

echo "Installed $binary_name to $install_dir/$binary_name"
echo "Run: $install_dir/$binary_name --help"
