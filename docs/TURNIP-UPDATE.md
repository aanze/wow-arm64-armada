# Mettre à jour Turnip (Mesa) pour WoW Forever sur Armada

## Pourquoi un Turnip à part

Le pilote Vulkan d'Armada (Mesa 26.2.x) plante en compilant deux shaders de l'écran de connexion de
WoW (`vkCreateGraphicsPipelines`, exception `0xc0000005` dans l'appel Unix). On utilise donc, **pour le
seul raccourci WoW Forever**, un Turnip compilé depuis Mesa en amont avec deux patchs de
[jareqpl/steam-frame-fixes](https://github.com/jareqpl/steam-frame-fixes) :

| Patch | Effet |
|---|---|
| `0001-tu-fail-pipeline-creation-when-ir3-shader-compilatio.patch` | un échec de compilation de shader renvoie une erreur au lieu de planter |
| `0002-ir3-log-why-shader-compilation-failed.patch` | journalise la cause de l'échec |

Les autres jeux, Battle.net et le bureau continuent d'utiliser le Mesa d'Armada.

## Fichiers du dépôt

| Fichier | Origine |
|---|---|
| `scripts/build-turnip.sh` | copié de jareqpl/steam-frame-fixes (licence MIT, voir `LICENSES/steam-frame-fixes-MIT.txt`) |
| `patches/mesa/0001-*.patch`, `patches/mesa/0002-*.patch` | idem |
| `scripts/install-turnip.sh` | installation sur l'Odin, versions côte à côte + lien `current` |
| `.github/workflows/build-turnip.yml` | compilation à la demande sur un runner GitHub arm64 |

Pour reprendre une version plus récente des fichiers de jareqpl :

```bash
B=https://raw.githubusercontent.com/jareqpl/steam-frame-fixes/HEAD
curl -fsSL -o scripts/build-turnip.sh "$B/scripts/build-turnip.sh"
curl -fsSL -o patches/mesa/0001-tu-fail-pipeline-creation-when-ir3-shader-compilatio.patch "$B/patches/mesa/0001-tu-fail-pipeline-creation-when-ir3-shader-compilatio.patch"
curl -fsSL -o patches/mesa/0002-ir3-log-why-shader-compilation-failed.patch "$B/patches/mesa/0002-ir3-log-why-shader-compilation-failed.patch"
```

Les patchs Mesa sont dans `patches/mesa/` : le workflow Proton n'applique que `patches/*.patch`,
il ne les voit donc pas.

## Mise en place initiale sur l'Odin (une seule fois)

Le Turnip actuel est dans `~/.local/share/wow-turnip/turnip/`. Pour passer à l'organisation par
versions, réinstalle-le avec le script (il le recopie dans un dossier versionné et crée `current`) :

```bash
scripts/install-turnip.sh \
  https://github.com/jareqpl/steam-frame-fixes/releases/download/v0.1-exp-20260917b/turnip-frame-v0.1-exp-20260917b.tar.xz \
  mesa-26.3.0-devel-e3a986f016
```

Puis, une seule fois, mets ces options de lancement sur le raccourci **WoW Forever** et redémarre Steam
(`steam -shutdown`, Armada le relance tout seul) :

```
VK_ICD_FILENAMES=/var/home/armada/.local/share/wow-turnip/current/freedreno_icd.aarch64.json VK_DRIVER_FILES=/var/home/armada/.local/share/wow-turnip/current/freedreno_icd.aarch64.json /usr/libexec/armada/armada-game-launch %command%
```

Ensuite, changer de version ne demande plus de toucher à Steam : le lien `current` suffit.
L'ancien dossier `~/.local/share/wow-turnip/turnip/` peut alors être supprimé.

## Mettre à jour

### 1. Choisir la version de Mesa

Dernières versions publiées : <https://gitlab.freedesktop.org/mesa/mesa/-/tags>.
Pour obtenir le SHA d'un tag ou de la branche principale :

```bash
git ls-remote https://gitlab.freedesktop.org/mesa/mesa.git "refs/tags/mesa-26.3.0^{}"
git ls-remote https://gitlab.freedesktop.org/mesa/mesa.git refs/heads/main
```

Préférer un tag de version stable (`mesa-26.3.x`) à la branche `main` : moins de surprises.

### 2. Compiler

**Option A, sur GitHub (recommandé)** : *Actions* → **build-turnip** → *Run workflow*, en donnant
le tag (ex. `mesa-26.3.0`) ou le SHA. Le workflow publie une pré-release
`turnip-<sha>-<n>` contenant l'archive et `SHA256SUMS`.

**Option B, directement sur l'Odin** (podman est disponible sur Armada, rien n'est installé sur le système) :

```bash
CONTAINER_ENGINE=podman MESA_COMMIT=<sha complet> scripts/build-turnip.sh
# résultat dans out/turnip/ ; pour l'installer :
(cd out && tar -cJf ../turnip-local.tar.xz turnip) && scripts/install-turnip.sh turnip-local.tar.xz
```

Le premier lancement télécharge l'image SDK de Valve (quelques Go).

### 3. Si un patch ne s'applique plus

`build-turnip.sh` s'arrête au `git am` si un patch entre en conflit avec la nouvelle version de Mesa.

1. Vérifier si le correctif a été intégré en amont :
   ```bash
   git -C build/turnip/mesa log --oneline -i --grep "fail pipeline creation" --grep "shader compilation failed" -n 5
   ```
2. **S'il est intégré** : supprimer le patch correspondant de `patches/mesa/`, et retirer de la boucle
   de vérification à la fin de `build-turnip.sh` la chaîne qu'il apportait
   (`failed to compile %s shader` pour le patch 0002).
3. **Sinon** : adapter le patch à la nouvelle version (ou garder l'ancienne version de Mesa).

### 4. Installer sur l'Odin

```bash
scripts/install-turnip.sh https://github.com/aanze/wow-arm64-armada/releases/download/<tag>/<archive>.tar.xz
```

Vérifie la somme avant si tu télécharges à la main : `sha256sum -c SHA256SUMS`.
Le script refuse d'écraser une version existante et bascule `current` sur la nouvelle.

### 5. Tester

1. Lancer **WoW Forever**, laisser la vidéo d'intro (elle mène à l'écran de connexion, qui contient
   les shaders problématiques), se connecter, entrer en jeu.
2. Vérifier quel pilote le jeu a chargé, pendant qu'il tourne :
   ```bash
   for p in $(pgrep -f WowB-ARM64.exe); do grep -h libvulkan_freedreno /proc/$p/maps; done | awk '{print $6}' | sort -u
   ```
   Le chemin doit être dans `~/.local/share/wow-turnip/<version>/`.

Pour un diagnostic, ajouter **temporairement** `PROTON_LOG=1` en tête des options de lancement.
Ne jamais jouer avec : le log grossit d'environ 100 Mo par seconde et fait ramer le jeu.

### 6. Revenir en arrière

```bash
scripts/install-turnip.sh --list              # la version active est marquée d'une *
scripts/install-turnip.sh --use <version>     # puis relancer le jeu
```

## Se passer du Turnip à part

Quand Armada livrera un Mesa ≥ 26.3, tester avec son pilote : retirer `VK_ICD_FILENAMES=…` et
`VK_DRIVER_FILES=…` des options de lancement, redémarrer Steam, lancer le jeu. Si l'écran de connexion
passe, supprimer `~/.local/share/wow-turnip`.

## Après une mise à jour d'Armada ou de Steam

Tout ce qui précède est dans `/var/home` et survit aux mises à jour d'Armada (bootc ne remplace que
`/usr`). En cas de problème après une mise à jour :

1. vérifier que le jeu charge toujours le bon pilote (commande du §5) ;
2. relancer une fois avec `PROTON_LOG=1` et chercher `err:vulkan` dans `~/steam-*.log` ;
3. si un changement du Steam Linux Runtime ARM64 casse le pilote, recompiler avec une image SDK plus
   récente : `SDK_IMAGE=registry.gitlab.steamos.cloud/proton/steamrt4/sdk/arm64-llvm:<tag> scripts/build-turnip.sh`.
