# Build and usage

## Build

```bash
make -C src build
make -C src check
make -C src build-native
make -C src compare
```

`make build` writes the latest local executable to `bin/sysfetch`.
`make build-native` writes the platform-specific release executable to
`release/`.

## Release packaging

From the repository root, build the native executable and create a portable
archive plus checksum:

```bash
make -C src check
make -C src compare
make -C src build-native
mkdir -p release/dist
tar -czf release/dist/sysfetch-0.2.0-$(uname -m)-$(uname -s | tr '[:upper:]' '[:lower:]').tar.gz \
  -C release "$(basename release/sysfetch-*)"
shasum -a 256 release/dist/* > release/dist/SHA256SUMS
```

The `bin/` directory contains the latest local executable. The `release/`
directory contains platform release executables; archives and checksums are
published to GitHub Releases.

`make -C src compare` runs the official Neofetch 7.1.0 script and compares
no-config, user-config, travis, and simple-function output. Live Memory and
Uptime samples are excluded because the two programs run at different times.

## Usage

```bash
./bin/sysfetch
./bin/sysfetch --json
./bin/sysfetch --stdout
./bin/sysfetch --travis
./bin/sysfetch --config ~/.config/neofetch/config.conf
./bin/sysfetch -L
./bin/sysfetch --ascii_distro arch -L
./bin/sysfetch --json | jq .
```

The JSON mode contains the Neofetch-compatible field labels and `Version`.
Optional collectors are included when available. Human output omits fields
that the host cannot detect, matching Neofetch's default behavior.
