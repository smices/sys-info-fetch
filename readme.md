# sysfetch

Nim system information CLI modeled on Neofetch.

## Release

Download the prebuilt archive for your platform from the
[GitHub Releases](https://github.com/smices/sys-info-fetch/releases) page.
Each archive has a matching SHA-256 checksum file.

```bash
make -C src build
./bin/sysfetch
./bin/sysfetch --json
./bin/sysfetch --hardware
./bin/sysfetch --json --hardware
./bin/sysfetch --travis
./bin/sysfetch --logo none --stdout
./bin/sysfetch -L
make -C src compare
```

The default field order and macOS collectors follow the official Neofetch
behavior. `--json` emits a Neofetch-compatible object with a `Version` key;
`--config` accepts Neofetch settings including `separator`, `colors`,
`color_blocks`, bar settings, `ascii_distro`, and custom `info` lines.

`-L/--logo` prints only the ASCII logo; `--stdout/--pipe` matches Neofetch's
non-color, no-logo output mode. `--travis` enables Neofetch's extended
collectors and infobars.

Hardware details are shown by default; `--hardware`/`--details` explicitly
enables them and `--no_hardware` restores the exact Neofetch field set. The
details include CPU topology, GPU cores and capabilities, memory module
information, and disk protocol/solid-state details when the operating system
exposes them. External USB, Thunderbolt, and Bluetooth devices include their
reported model and vendor when available. Linux uses `lscpu`, `lspci`,
`lsblk`, `lsusb`, and optional passwordless `dmidecode`; BSD uses `sysctl`,
`pciconf`, `geom`, and `acpiconf` where available.

`make -C src compare` runs the official Neofetch 7.1.0 script from GitHub and
compares default, configured, travis, and simple-function output. Memory and
Uptime are excluded because both programs sample them at different instants.

See [doc/BUILD.md](doc/BUILD.md) for build details.
