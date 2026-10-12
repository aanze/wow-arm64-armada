# Proton 11.0-2e ARM64 (Steam) + syscall dispatcher fix

Build of **Valve's Proton, tag [`proton-11.0-2e`](https://github.com/ValveSoftware/Proton/tree/proton-11.0-2e)**,
for **Linux ARM64 (glibc)**, as a Steam compatibility tool (Armada, etc.), with the
`patches/0001-ntdll-fixed-address-syscall-dispatcher-aarch64.patch` fix applied to the
wine submodule.

## How it is built

The `.github/workflows/build-proton-arm64.yml` workflow follows the "ARM64 Builds" section of
[Proton's README](https://github.com/ValveSoftware/Proton/blob/proton_11.0/README.md):

- GitHub ARM64 runner (`ubuntu-24.04-arm`): Valve requires an ARM64 build machine;
- `configure.sh --target-arch=arm64`, then `make redist`; everything is built inside
  Valve's SDK container (`registry.gitlab.steamos.cloud/proton/steamrt4/sdk/arm64-llvm`);
- the patch is applied to the `wine` submodule (`ValveSoftware/wine@e60892c`) before the build;
- after the build, `scripts/check-thunks.py` checks that **all** syscall thunks of the produced
  aarch64 `ntdll.dll` load the pointer from `0x7ffe1000`, and fails the build otherwise.

A full Proton build on a 4-core runner takes a long time. `make` is stopped at 5 h 20 min to
stay under GitHub's 6 h job limit; the ccache cache is saved in every case, so **re-running the
workflow** ("Re-run jobs") resumes where it stopped.

## Installation

Each successful build publishes a `proton-11.0-2e-arm64-fix-<n>` pre-release containing
`proton-11.0-2e-arm64-fix.tar.xz`:

```sh
mkdir -p ~/.steam/root/compatibilitytools.d
tar -xJf proton-11.0-2e-arm64-fix.tar.xz -C ~/.steam/root/compatibilitytools.d/
```

Restart Steam, then pick `proton-11.0-2e-arm64-fix` in the game's Properties > Compatibility.
Valve's ARM64 `toolmanifest.vdf` requires the Steam tool with appid `4185400`, which Steam
installs by itself.

## Additional steps for World of Warcraft (native ARM64 client) on Armada

The Proton build alone is not enough for the native `WowB-ARM64.exe` client. Two additions:

1. **Pure ARM64 DXVK / vkd3d-proton.** Proton 11.0 (ARM64) ships these DLLs as ARM64EC, which a
   pure ARM64 process cannot load (`LoadLibrary(dxgi.dll) Failed (HR:0x000000C1)`).
   After extracting the tool, replace them with the ones from Proton Experimental (ARM64):

   ```sh
   scripts/install-dxvk-arm64.sh ~/.local/share/Steam/compatibilitytools.d/proton-11.0-2e-arm64-fix
   ```

2. **A Turnip Vulkan driver newer than Armada's.** Mesa 26.2.x crashes while compiling two
   login-screen shaders (`err:vulkan:vkCreateGraphicsPipelines Exception 0xc0000005`).
   A Turnip built from upstream Mesa, with two patches from
   [jareqpl/steam-frame-fixes](https://github.com/jareqpl/steam-frame-fixes), is used for the
   game's shortcut only. Building, installing and updating it: [`docs/TURNIP-UPDATE.md`](docs/TURNIP-UPDATE.md).

Launch options of the shortcut (which starts `WowB-ARM64.exe` directly):

```
VK_ICD_FILENAMES=/var/home/armada/.local/share/wow-turnip/current/freedreno_icd.aarch64.json VK_DRIVER_FILES=/var/home/armada/.local/share/wow-turnip/current/freedreno_icd.aarch64.json /usr/libexec/armada/armada-game-launch %command%
```

Do not play with `PROTON_LOG=1`: the log grows by about 100 MB/s and makes the game lag.

## The fix

The aarch64 syscall thunks loaded the address of `__wine_syscall_dispatcher` through a literal
pointing to a variable in ntdll's data section. An application that runs the thunks from its own
copy of ntdll (e.g. the anti-tamper code of the native ARM64 World of Warcraft client, see
[Winlator-Ludashi#632](https://github.com/StevenMXZ/Winlator-Ludashi/issues/632)) reads that
variable as 0 and jumps to address 0 (`c0000005`, `pc=0`, `x16=0`). The fix does what x86_64
does: the pointer is stored at the fixed address `0x7ffe1000`, right after the
`KUSER_SHARED_DATA` page.

### Known limitation: 16 KB page kernels

`0x7ffe1000` is not 16 KB aligned. On a kernel with 16 KB pages, `anon_mmap_fixed()` fails and
this address falls into the host page of `KUSER_SHARED_DATA`, which is read-only: writing the
pointer in `signal_init_process()` should crash every process at startup. Analysis based on the
code (`dlls/ntdll/unix/virtual.c`), not tested on a device.
Check with `getconf PAGE_SIZE` (it must print `4096`).
