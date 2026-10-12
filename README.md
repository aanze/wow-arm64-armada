# Proton 11.0-2 arm64ec + correctif du dispatcher de syscalls (aarch64)

Build de **GameNative Proton Wine 11.0-2 arm64ec** (Android/bionic, pour GameNative et
Winlator CMOD/Ludashi) avec le correctif `patches/0001-ntdll-fixed-address-syscall-dispatcher-aarch64.patch`.

## Ce qui est compilé

| Élément | Version |
|---|---|
| Sources Wine | [`GameNative/proton-wine@f323a4d`](https://github.com/GameNative/proton-wine/commit/f323a4d3eb4387bab684710ca1b38251ca7854e1), branche `proton_11.0-2`, même commit que la release officielle `proton-11.0-2-20261010` |
| Script de build | `build-scripts/build-step-arm64ec.sh` de ces sources (applique la série `android/patches`) |
| Toolchains | Android NDK r27d, [bylaws/llvm-mingw 20250920](https://github.com/bylaws/llvm-mingw/releases/tag/20250920) |
| ntsync-android | [`GameNative/ntsync-android@7ce6435`](https://github.com/GameNative/ntsync-android/commit/7ce6435e5979b1cb5341aa4b299f31e8937fe121) |
| Correctif | `patches/*.patch`, appliqué après la série `android/patches` |

Le workflow `.github/workflows/build-arm64ec.yml` reprend la branche aarch64 du
[workflow officiel](https://github.com/GameNative/proton-wine/blob/proton_11.0-2/.github/workflows/build-proton.yml).
Il vérifie ensuite dans le `ntdll.dll` aarch64 produit que **tous** les thunks de syscall
chargent le pointeur depuis `0x7ffe1000` (`scripts/check-thunks.py`), et échoue sinon.

## Récupérer le build

Chaque push lance le workflow, qui publie une pré-release
(`proton-11.0-2-fix-arm64ec-<n>`) et des artefacts Actions :

- `proton-11.0-2-fix-arm64ec.wcp` : type Proton, pour GameNative
- `proton-wine-11.0-2-fix-arm64ec.wcp.xz` : type Wine, pour Winlator CMOD / Ludashi

Le nom de version (`11.0-2-fix-arm64ec`) diffère de celui du build officiel, les deux
peuvent donc être installés côte à côte. Il faut un conteneur arm64ec neuf.

## Le correctif

Les thunks de syscall aarch64 chargeaient l'adresse de `__wine_syscall_dispatcher`
via un littéral pointant vers une variable de la section data de ntdll. Une application
qui exécute les thunks depuis sa propre copie de ntdll (ex. l'anti-tamper du client
natif ARM64 de World of Warcraft, cf.
[Winlator-Ludashi#632](https://github.com/StevenMXZ/Winlator-Ludashi/issues/632))
lit cette variable à 0 et saute à l'adresse 0 (`c0000005`, `pc=0`, `x16=0`).
Le correctif fait comme x86_64 : le pointeur est stocké à l'adresse fixe `0x7ffe1000`,
juste après la page `KUSER_SHARED_DATA`.

### Limite connue : noyaux à pages de 16 Ko

`0x7ffe1000` n'est pas aligné sur 16 Ko. Sur un appareil dont le noyau utilise des pages
de 16 Ko, `anon_mmap_fixed()` échoue (adresse non alignée) et cette adresse tombe dans la
même page hôte que `KUSER_SHARED_DATA`, mappée en lecture seule : l'écriture du pointeur
dans `signal_init_process()` devrait alors provoquer un crash au démarrage de chaque
processus. Analyse faite sur le code (`dlls/ntdll/unix/virtual.c` :
`host_page_size = sysconf(_SC_PAGESIZE)`, `page_size = 0x1000`), non testée sur appareil.
Sur les appareils à pages de 4 Ko (la grande majorité aujourd'hui), le problème ne se pose pas.
