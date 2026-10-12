#!/usr/bin/env bash
# Installs a Turnip build on the device (run it ON the device) as a separate version,
# then points the "current" link to it. Previous versions are kept for rollback.
#
# Usage:
#   scripts/install-turnip.sh <archive.tar.xz | URL> [version-name]
#   scripts/install-turnip.sh --use <version-name>     # switch back to an installed version
#   scripts/install-turnip.sh --list
#
# Layout:
#   ~/.local/share/wow-turnip/<version>/libvulkan_freedreno.so
#   ~/.local/share/wow-turnip/<version>/freedreno_icd.aarch64.json   (library_path -> this folder)
#   ~/.local/share/wow-turnip/current -> <version>
# Launch options of the shortcut (set once):
#   VK_ICD_FILENAMES=$HOME/.local/share/wow-turnip/current/freedreno_icd.aarch64.json \
#   VK_DRIVER_FILES=$HOME/.local/share/wow-turnip/current/freedreno_icd.aarch64.json \
#   /usr/libexec/armada/armada-game-launch %command%

set -euo pipefail
BASE="${WOW_TURNIP_DIR:-$HOME/.local/share/wow-turnip}"
die() { echo "error: $*" >&2; exit 1; }

mkdir -p "$BASE"
case "${1:-}" in
    --list)
        for d in "$BASE"/*/; do
            [[ -L "${d%/}" ]] && continue
            [[ -f "$d/libvulkan_freedreno.so" ]] || continue
            n=$(basename "$d"); mark=" "; [[ "$(readlink "$BASE/current" 2>/dev/null)" == "$n" ]] && mark="*"
            printf '%s %-40s %s\n' "$mark" "$n" "$(grep -m1 '^mesa_version' "$d/BUILDINFO" 2>/dev/null | cut -d' ' -f2)"
        done; exit 0 ;;
    --use)
        [[ -f "$BASE/${2:-}/freedreno_icd.aarch64.json" ]] || die "unknown version: ${2:-}"
        ln -sfn "$2" "$BASE/current"; echo "current -> $2"; exit 0 ;;
    ""|-h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

src="$1"; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
if [[ "$src" =~ ^https?:// ]]; then
    curl -fL --retry 3 -o "$tmp/turnip.tar.xz" "$src"; src="$tmp/turnip.tar.xz"
fi
[[ -f "$src" ]] || die "archive not found: $src"
tar -tJf "$src" | grep -qE '^/|(^|/)\.\.(/|$)' && die "suspicious archive (absolute path or ..)"
tar -xJf "$src" -C "$tmp"
lib=$(find "$tmp" -name libvulkan_freedreno.so -type f | head -n1)
[[ -n "$lib" ]] || die "no libvulkan_freedreno.so in the archive"
dir=$(dirname "$lib")
[[ -f "$dir/freedreno_icd.aarch64.json.in" ]] || die "no freedreno_icd.aarch64.json.in"
file -b "$lib" | grep -q 'ARM aarch64' || die "the library is not aarch64"

name="${2:-}"
if [[ -z "$name" ]]; then
    ver=$(grep -m1 '^mesa_version' "$dir/BUILDINFO" 2>/dev/null | cut -d' ' -f2)
    sha=$(grep -m1 '^mesa_commit' "$dir/BUILDINFO" 2>/dev/null | cut -d' ' -f2 | cut -c1-10)
    name="mesa-${ver:-unknown}-${sha:-$(date +%Y%m%d%H%M)}"
fi
dest="$BASE/$name"
[[ -e "$dest" ]] && die "$dest already exists (pick another version name)"
mkdir -p "$dest"; cp -a "$dir"/. "$dest"/
sed "s|@LIBPATH@|$dest/libvulkan_freedreno.so|" "$dest/freedreno_icd.aarch64.json.in" > "$dest/freedreno_icd.aarch64.json"
ln -sfn "$name" "$BASE/current"
echo "installed: $dest"
echo "current -> $name   (just restart the game, Steam does not need a restart)"
