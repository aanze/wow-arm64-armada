#!/usr/bin/env bash
# Remplace, dans un outil Proton ARM64, le DXVK et le vkd3d-proton ARM64EC par les versions ARM64
# pures fournies par "Proton Experimental (ARM64)" de Valve.
#
# Pourquoi : un jeu Windows compilé en ARM64 pur (ex. WowB-ARM64.exe) ne peut pas charger une DLL
# ARM64EC ; le jeu échoue alors avec « LoadLibrary(dxgi.dll) Failed (HR:0x000000C1) ». Proton 11.0
# (ARM64) ne livre que des DXVK/vkd3d ARM64EC, Proton Experimental (ARM64) livre des versions ARM64 pures.
# Proton recopie ces DLL dans le préfixe à chaque lancement : il faut donc les remplacer dans l'outil,
# pas dans le préfixe.
#
# Usage : scripts/install-dxvk-arm64.sh <dossier de l'outil Proton> [dossier de Proton Experimental (ARM64)]
# Les DLL d'origine sont gardées dans <...>/aarch64-windows.orig/.

set -euo pipefail
TOOL="${1:?usage: $0 <dossier-outil-proton> [source]}"
SRC="${2:-$HOME/.local/share/Steam/steamapps/common/Proton Experimental (ARM64)}"
machine() {
    python3 -I -c 'import struct,sys
d = open(sys.argv[1], "rb").read(4096)
o = struct.unpack_from("<I", d, 0x3c)[0]
print({0xaa64: "arm64", 0x8664: "arm64ec/x64"}.get(struct.unpack_from("<H", d, o + 4)[0], "?"))' "$1"
}
copy_dlls() {  # <sous-dossier> <dll...>
    local d="$1"; shift
    local s="$SRC/files/lib/wine/$d/aarch64-windows" t="$TOOL/files/lib/wine/$d/aarch64-windows" n
    [[ -d "$s" ]] || { echo "erreur: source introuvable: $s" >&2; exit 1; }
    [[ -d "$t" ]] || { echo "erreur: cible introuvable: $t" >&2; exit 1; }
    for n in "$@"; do
        [[ "$(machine "$s/$n.dll")" == arm64 ]] || { echo "erreur: $s/$n.dll n'est pas en ARM64 pur" >&2; exit 1; }
    done
    [[ -d "$t.orig" ]] || cp -a "$t" "$t.orig"
    for n in "$@"; do cp -f "$s/$n.dll" "$t/"; done
}
copy_dlls dxvk d3d8 d3d9 d3d10core d3d11 dxgi
copy_dlls vkd3d-proton d3d12 d3d12core
for f in dxvk/aarch64-windows/dxgi.dll dxvk/aarch64-windows/d3d11.dll vkd3d-proton/aarch64-windows/d3d12.dll; do
    printf '%-40s %s\n' "$f" "$(machine "$TOOL/files/lib/wine/$f")"
done
echo "OK. Redémarrer Steam n'est pas nécessaire : Proton recopie les DLL au prochain lancement du jeu."
