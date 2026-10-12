#!/usr/bin/env bash
# Replaces, in a Proton ARM64 tool, the ARM64EC DXVK and vkd3d-proton with the pure ARM64
# versions shipped by Valve's "Proton Experimental (ARM64)".
#
# Why: a Windows game built as pure ARM64 (e.g. WowB-ARM64.exe) cannot load an ARM64EC DLL; the
# game then fails with "LoadLibrary(dxgi.dll) Failed (HR:0x000000C1)". Proton 11.0 (ARM64) only ships
# ARM64EC DXVK/vkd3d, Proton Experimental (ARM64) ships pure ARM64 ones. Proton copies these DLLs into
# the prefix on every launch, so they must be replaced in the tool, not in the prefix.
#
# Usage: scripts/install-dxvk-arm64.sh <proton-tool-dir> [Proton Experimental (ARM64) dir]
# The original DLLs are kept in <...>/aarch64-windows.orig/.

set -euo pipefail
TOOL="${1:?usage: $0 <proton-tool-dir> [source]}"
SRC="${2:-$HOME/.local/share/Steam/steamapps/common/Proton Experimental (ARM64)}"
machine() {
    python3 -I -c 'import struct,sys
d = open(sys.argv[1], "rb").read(4096)
o = struct.unpack_from("<I", d, 0x3c)[0]
print({0xaa64: "arm64", 0x8664: "arm64ec/x64"}.get(struct.unpack_from("<H", d, o + 4)[0], "?"))' "$1"
}
copy_dlls() {  # <subfolder> <dll...>
    local d="$1"; shift
    local s="$SRC/files/lib/wine/$d/aarch64-windows" t="$TOOL/files/lib/wine/$d/aarch64-windows" n
    [[ -d "$s" ]] || { echo "error: source not found: $s" >&2; exit 1; }
    [[ -d "$t" ]] || { echo "error: target not found: $t" >&2; exit 1; }
    for n in "$@"; do
        [[ "$(machine "$s/$n.dll")" == arm64 ]] || { echo "error: $s/$n.dll is not pure ARM64" >&2; exit 1; }
    done
    [[ -d "$t.orig" ]] || cp -a "$t" "$t.orig"
    for n in "$@"; do cp -f "$s/$n.dll" "$t/"; done
}
copy_dlls dxvk d3d8 d3d9 d3d10core d3d11 dxgi
copy_dlls vkd3d-proton d3d12 d3d12core
for f in dxvk/aarch64-windows/dxgi.dll dxvk/aarch64-windows/d3d11.dll vkd3d-proton/aarch64-windows/d3d12.dll; do
    printf '%-40s %s\n' "$f" "$(machine "$TOOL/files/lib/wine/$f")"
done
echo "OK. No Steam restart needed: Proton copies the DLLs again on the next game launch."
