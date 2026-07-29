#!/usr/bin/env bash

set -euo pipefail

nim_bin="${NIM:-nim}"
root_dir=".."
release_dir="$root_dir/release"
host_arch="$(uname -m)"
host_os="$(uname -s | tr '[:upper:]' '[:lower:]')"
if [[ "$host_os" == "darwin" && "$host_arch" == "arm64" ]]; then
    target="aarch64-apple-darwin"
elif [[ "$host_os" == "darwin" && "$host_arch" == "x86_64" ]]; then
    target="x86_64-apple-darwin"
elif [[ "$host_os" == "linux" && "$host_arch" == "x86_64" ]]; then
    target="x86_64-unknown-linux-gnu"
else
    target="${host_arch}-${host_os}"
fi
output="$release_dir/sysfetch-$target"

mkdir -p "$release_dir"
"$nim_bin" c -d:release -o:"$output" sysfetch.nim
chmod 755 "$output"
echo "✓ $output"
