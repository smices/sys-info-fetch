#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="${root_dir}/bin/sysfetch"
source_url="https://raw.githubusercontent.com/dylanaraps/neofetch/master/neofetch"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/sysfetch-compare.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

if [[ ! -x "$binary" ]]; then
    echo "missing executable: $binary (run make -C src build first)" >&2
    exit 2
fi

normalize() {
    sed -E 's/[[:space:]]+$//' "$1" | sed -E '/^(Memory|Uptime|Local IP|Public IP):/d' | sed -E '/^[0-9]+ (day|days|hour|hours|min|mins)(,|$)/d'
}

compare_mode() {
    local name="$1"
    shift
    SYSFETCH_NEofETCH_COMPAT=1 "$binary" "$@" --stdout >"$work_dir/sysfetch.${name}"
    curl -fsSL "$source_url" | bash -s -- "$@" --stdout >"$work_dir/neofetch.${name}"
    normalize "$work_dir/neofetch.${name}" >"$work_dir/neofetch.${name}.normalized"
    normalize "$work_dir/sysfetch.${name}" >"$work_dir/sysfetch.${name}.normalized"
    if ! diff -u "$work_dir/neofetch.${name}.normalized" "$work_dir/sysfetch.${name}.normalized"; then
        echo "Neofetch comparison failed: ${name}." >&2
        exit 1
    fi
}

compare_mode no-config --no_config
compare_mode user-config
compare_mode travis --no_config --travis
compare_mode simple-functions --no_config os distro model kernel packages shell de wm wm_theme theme icons term term_font cpu gpu
echo "Neofetch comparisons passed (live Memory, Uptime, and IP values excluded)."
