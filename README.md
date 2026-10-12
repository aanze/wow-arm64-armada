# Proton 11.0-2e ARM64 (Steam) + correctif du dispatcher de syscalls

Build de **Proton de Valve, tag [`proton-11.0-2e`](https://github.com/ValveSoftware/Proton/tree/proton-11.0-2e)**,
pour **Linux ARM64 (glibc)**, en tant qu'outil de compatibilité Steam (Armada, etc.), avec le
correctif `patches/0001-ntdll-fixed-address-syscall-dispatcher-aarch64.patch` appliqué au
sous-module wine.

## Comment c'est compilé

Le workflow `.github/workflows/build-proton-arm64.yml` suit la section « ARM64 Builds » du
[README de Proton](https://github.com/ValveSoftware/Proton/blob/proton_11.0/README.md) :

- runner GitHub ARM64 (`ubuntu-24.04-arm`) : Valve exige une machine de build ARM64 ;
- `configure.sh --target-arch=arm64`, puis `make redist` ; tout est compilé dans le
  conteneur SDK de Valve (`registry.gitlab.steamos.cloud/proton/steamrt4/sdk/arm64-llvm`) ;
- le patch est appliqué au sous-module `wine` (`ValveSoftware/wine@e60892c`) avant le build ;
- après le build, `scripts/check-thunks.py` vérifie que **tous** les thunks de syscall du
  `ntdll.dll` aarch64 produit chargent le pointeur depuis `0x7ffe1000`, et fait échouer le build sinon.

Un build complet de Proton sur un runner à 4 cœurs est long. `make` est arrêté à 5 h 20
pour rester sous la limite de 6 h d'un job GitHub ; le cache ccache est sauvegardé
dans tous les cas, donc **relancer le workflow** (« Re-run jobs ») reprend là où il s'était arrêté.

## Installation

Chaque build réussi publie une pré-release `proton-11.0-2e-arm64-fix-<n>` contenant
`proton-11.0-2e-arm64-fix.tar.xz` :

```sh
mkdir -p ~/.steam/root/compatibilitytools.d
tar -xJf proton-11.0-2e-arm64-fix.tar.xz -C ~/.steam/root/compatibilitytools.d/
```

Redémarrer Steam, puis choisir `proton-11.0-2e-arm64-fix` dans Propriétés > Compatibilité du jeu.
Le `toolmanifest.vdf` ARM64 de Valve requiert l'outil Steam d'appid `4185400`, que Steam
installe lui-même.

## Le correctif

Les thunks de syscall aarch64 chargeaient l'adresse de `__wine_syscall_dispatcher` via un
littéral pointant vers une variable de la section data de ntdll. Une application qui exécute
les thunks depuis sa propre copie de ntdll (ex. l'anti-tamper du client natif ARM64 de
World of Warcraft, cf. [Winlator-Ludashi#632](https://github.com/StevenMXZ/Winlator-Ludashi/issues/632))
lit cette variable à 0 et saute à l'adresse 0 (`c0000005`, `pc=0`, `x16=0`). Le correctif fait
comme x86_64 : le pointeur est stocké à l'adresse fixe `0x7ffe1000`, juste après la page
`KUSER_SHARED_DATA`.

### Limite connue : noyaux à pages de 16 Ko

`0x7ffe1000` n'est pas aligné sur 16 Ko. Sur un noyau à pages de 16 Ko, `anon_mmap_fixed()`
échoue et cette adresse tombe dans la page hôte de `KUSER_SHARED_DATA`, en lecture seule :
l'écriture du pointeur dans `signal_init_process()` devrait faire planter chaque processus au
démarrage. Analyse faite sur le code (`dlls/ntdll/unix/virtual.c`), non testée sur appareil.
Vérifier avec `getconf PAGE_SIZE` (doit afficher `4096`).
