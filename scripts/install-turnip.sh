#!/usr/bin/env bash
# Installe une build de Turnip sur l'appareil (à lancer SUR l'Odin), dans une version à part,
# puis fait pointer le lien "current" dessus. Les versions précédentes restent pour le rollback.
#
# Usage:
#   scripts/install-turnip.sh <archive.tar.xz | URL> [nom-de-version]
#   scripts/install-turnip.sh --use <nom-de-version>     # rebascule sur une version déjà installée
#   scripts/install-turnip.sh --list
#
# Arborescence :
#   ~/.local/share/wow-turnip/<version>/libvulkan_freedreno.so
#   ~/.local/share/wow-turnip/<version>/freedreno_icd.aarch64.json   (library_path -> ce dossier)
#   ~/.local/share/wow-turnip/current -> <version>
# Options de lancement du raccourci (à régler une seule fois) :
#   VK_ICD_FILENAMES=$HOME/.local/share/wow-turnip/current/freedreno_icd.aarch64.json \
#   VK_DRIVER_FILES=$HOME/.local/share/wow-turnip/current/freedreno_icd.aarch64.json \
#   /usr/libexec/armada/armada-game-launch %command%

set -euo pipefail
BASE="${WOW_TURNIP_DIR:-$HOME/.local/share/wow-turnip}"
die() { echo "erreur: $*" >&2; exit 1; }

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
        [[ -f "$BASE/${2:-}/freedreno_icd.aarch64.json" ]] || die "version inconnue: ${2:-}"
        ln -sfn "$2" "$BASE/current"; echo "current -> $2"; exit 0 ;;
    ""|-h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

src="$1"; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
if [[ "$src" =~ ^https?:// ]]; then
    curl -fL --retry 3 -o "$tmp/turnip.tar.xz" "$src"; src="$tmp/turnip.tar.xz"
fi
[[ -f "$src" ]] || die "archive introuvable: $src"
tar -tJf "$src" | grep -qE '^/|(^|/)\.\.(/|$)' && die "archive suspecte (chemin absolu ou ..)"
tar -xJf "$src" -C "$tmp"
lib=$(find "$tmp" -name libvulkan_freedreno.so -type f | head -n1)
[[ -n "$lib" ]] || die "pas de libvulkan_freedreno.so dans l'archive"
dir=$(dirname "$lib")
[[ -f "$dir/freedreno_icd.aarch64.json.in" ]] || die "pas de freedreno_icd.aarch64.json.in"
file -b "$lib" | grep -q 'ARM aarch64' || die "la bibliothèque n'est pas aarch64"

name="${2:-}"
if [[ -z "$name" ]]; then
    ver=$(grep -m1 '^mesa_version' "$dir/BUILDINFO" 2>/dev/null | cut -d' ' -f2)
    sha=$(grep -m1 '^mesa_commit' "$dir/BUILDINFO" 2>/dev/null | cut -d' ' -f2 | cut -c1-10)
    name="mesa-${ver:-unknown}-${sha:-$(date +%Y%m%d%H%M)}"
fi
dest="$BASE/$name"
[[ -e "$dest" ]] && die "$dest existe déjà (choisis un autre nom de version)"
mkdir -p "$dest"; cp -a "$dir"/. "$dest"/
sed "s|@LIBPATH@|$dest/libvulkan_freedreno.so|" "$dest/freedreno_icd.aarch64.json.in" > "$dest/freedreno_icd.aarch64.json"
ln -sfn "$name" "$BASE/current"
echo "installé : $dest"
echo "current -> $name   (relance simplement le jeu, Steam n'a pas besoin de redémarrer)"
