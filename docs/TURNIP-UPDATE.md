# Updating Turnip (Mesa) for WoW Forever on Armada

## Why a separate Turnip

Armada's Vulkan driver (Mesa 26.2.x) crashes while compiling two shaders of the WoW login screen
(`vkCreateGraphicsPipelines`, exception `0xc0000005` in the Unix call). **For the WoW Forever
shortcut only**, we therefore use a Turnip built from upstream Mesa with two patches from
[jareqpl/steam-frame-fixes](https://github.com/jareqpl/steam-frame-fixes):

| Patch | Effect |
|---|---|
| `0001-tu-fail-pipeline-creation-when-ir3-shader-compilatio.patch` | a shader compilation failure returns an error instead of crashing |
| `0002-ir3-log-why-shader-compilation-failed.patch` | logs why the compilation failed |

Other games, Battle.net and the desktop keep using Armada's Mesa.

## Repository files

| File | Origin |
|---|---|
| `scripts/build-turnip.sh` | copied from jareqpl/steam-frame-fixes (MIT license, see `LICENSES/steam-frame-fixes-MIT.txt`) |
| `patches/mesa/0001-*.patch`, `patches/mesa/0002-*.patch` | same |
| `scripts/install-turnip.sh` | installs on the device, side-by-side versions + a `current` link |
| `.github/workflows/build-turnip.yml` | on-demand build on a GitHub arm64 runner |

To pull a newer version of jareqpl's files:

```bash
B=https://raw.githubusercontent.com/jareqpl/steam-frame-fixes/HEAD
curl -fsSL -o scripts/build-turnip.sh "$B/scripts/build-turnip.sh"
curl -fsSL -o patches/mesa/0001-tu-fail-pipeline-creation-when-ir3-shader-compilatio.patch "$B/patches/mesa/0001-tu-fail-pipeline-creation-when-ir3-shader-compilatio.patch"
curl -fsSL -o patches/mesa/0002-ir3-log-why-shader-compilation-failed.patch "$B/patches/mesa/0002-ir3-log-why-shader-compilation-failed.patch"
```

The Mesa patches live in `patches/mesa/`: the Proton workflow only applies `patches/*.patch`,
so it does not pick them up.

## Initial setup on the device (once)

Install the current Turnip build with the script (it goes into a versioned folder and `current`
points to it):

```bash
scripts/install-turnip.sh \
  https://github.com/jareqpl/steam-frame-fixes/releases/download/v0.1-exp-20260917b/turnip-frame-v0.1-exp-20260917b.tar.xz \
  mesa-26.3.0-devel-e3a986f016
```

Then, once, set these launch options on the **WoW Forever** shortcut and restart Steam
(`steam -shutdown`, Armada starts it again by itself):

```
VK_ICD_FILENAMES=/var/home/armada/.local/share/wow-turnip/current/freedreno_icd.aarch64.json VK_DRIVER_FILES=/var/home/armada/.local/share/wow-turnip/current/freedreno_icd.aarch64.json /usr/libexec/armada/armada-game-launch %command%
```

From then on, switching versions does not require touching Steam: the `current` link is enough.

## Updating

### 1. Pick the Mesa version

Released versions: <https://gitlab.freedesktop.org/mesa/mesa/-/tags>.
To get the SHA of a tag or of the main branch:

```bash
git ls-remote https://gitlab.freedesktop.org/mesa/mesa.git "refs/tags/mesa-26.3.0^{}"
git ls-remote https://gitlab.freedesktop.org/mesa/mesa.git refs/heads/main
```

Prefer a stable release tag (`mesa-26.3.x`) over the `main` branch: fewer surprises.

### 2. Build

**Option A, on GitHub (recommended):** *Actions* → **build-turnip** → *Run workflow*, with the
tag (e.g. `mesa-26.3.0`) or the SHA. The workflow publishes a `turnip-<sha>-<n>` pre-release
containing the archive and `SHA256SUMS`.

**Option B, directly on the device** (podman is available on Armada, nothing gets installed on the system):

```bash
CONTAINER_ENGINE=podman MESA_COMMIT=<full sha> scripts/build-turnip.sh
# output in out/turnip/; to install it:
(cd out && tar -cJf ../turnip-local.tar.xz turnip) && scripts/install-turnip.sh turnip-local.tar.xz
```

The first run downloads Valve's SDK image (a few GB).

### 3. If a patch no longer applies

`build-turnip.sh` stops at `git am` when a patch conflicts with the new Mesa version.

1. Check whether the fix was merged upstream:
   ```bash
   git -C build/turnip/mesa log --oneline -i --grep "fail pipeline creation" --grep "shader compilation failed" -n 5
   ```
2. **If it was merged:** delete the corresponding patch from `patches/mesa/`, and remove the string
   it introduced from the verification loop at the end of `build-turnip.sh`
   (`failed to compile %s shader` for patch 0002).
3. **Otherwise:** rebase the patch onto the new version (or stay on the previous Mesa version).

### 4. Install on the device

```bash
scripts/install-turnip.sh https://github.com/aanze/wow-arm64-armada/releases/download/<tag>/<archive>.tar.xz
```

Check the checksum first if you download by hand: `sha256sum -c SHA256SUMS`.
The script refuses to overwrite an existing version and switches `current` to the new one.

### 5. Test

1. Start **WoW Forever**, let the intro video play (it leads to the login screen, which contains
   the problematic shaders), log in, enter the world.
2. Check which driver the game loaded, while it runs:
   ```bash
   for p in $(pgrep -f WowB-ARM64.exe); do grep -h libvulkan_freedreno /proc/$p/maps; done | awk '{print $6}' | sort -u
   ```
   The path must be under `~/.local/share/wow-turnip/<version>/`.

For diagnostics, add `PROTON_LOG=1` **temporarily** at the start of the launch options.
Never play with it: the log grows by about 100 MB/s and makes the game lag.

### 6. Roll back

```bash
scripts/install-turnip.sh --list              # the active version is marked with *
scripts/install-turnip.sh --use <version>     # then restart the game
```

## Dropping the separate Turnip

Once Armada ships Mesa ≥ 26.3, test with its driver: remove `VK_ICD_FILENAMES=…` and
`VK_DRIVER_FILES=…` from the launch options, restart Steam, start the game. If the login screen
loads, delete `~/.local/share/wow-turnip`.

## After an Armada or Steam update

Everything above lives in `/var/home` and survives Armada updates (bootc only replaces `/usr`).
If something breaks after an update:

1. check that the game still loads the right driver (command from §5);
2. run once with `PROTON_LOG=1` and look for `err:vulkan` in `~/steam-*.log`;
3. if a Steam Linux Runtime ARM64 change breaks the driver, rebuild with a newer SDK image:
   `SDK_IMAGE=registry.gitlab.steamos.cloud/proton/steamrt4/sdk/arm64-llvm:<tag> scripts/build-turnip.sh`.
