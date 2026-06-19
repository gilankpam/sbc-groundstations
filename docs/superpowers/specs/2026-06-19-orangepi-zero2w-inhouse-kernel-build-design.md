# Orange Pi Zero 2W — in-house kernel build (drop the Armbian-tree dependency) — design

**Date:** 2026-06-19
**Repos touched:** `sbc-groundstations` (Orange Pi Zero 2W board only)
**Status:** approved design, pending implementation plan
**Supersedes:** the kernel-sourcing half of `2026-06-17-orangepi-zero2w-h618-design.md`
(commit `9267c77`, "pivot kernel to Armbian-patched source snapshot"). U-Boot, ATF,
the video/ffmpeg path, and the wfb stack are unchanged by this work.

## Context

The Orange Pi Zero 2W kernel is currently built by Buildroot from a **pre-patched
source snapshot tarball**:

```
configs/orangepi_zero2w_defconfig
  BR2_LINUX_KERNEL_CUSTOM_TARBALL=y
  BR2_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION="file://${...}/.opi-artifacts/linux-6.18.35-opi-sunxi.tar.gz"
```

That 350 MB tarball is gitignored and produced out-of-band by
`scripts/prepare-opi-artifacts.sh`, which snapshots an **Armbian build tree** at
`~/h618-kernel-work/armbian-build` (kernel worktree
`cache/sources/linux-kernel-worktree/6.18__sunxi64__arm64`). Buildroot only runs
`make`; all source-prep (fetch mainline + patch) happens in Armbian.

This makes the Armbian tree an **undocumented, machine-specific hard prerequisite**:
a fresh clone cannot build this board until the operator regenerates
`.opi-artifacts/` from a correctly-configured Armbian tree. Nothing in the repo
(`README.md`, `build.sh`, `Dockerfile`, `shell.nix`) documents or invokes this.

How Armbian produces that source today (established by investigation):

- **Source:** mainline Linux **stable, tag `v6.18.35`** (sunxi64 is a *mainline*
  family — it does not pin a vendor fork; `KERNELSOURCE` falls through to
  `MAINLINE_KERNEL_SOURCE`, `KERNELBRANCH` auto-resolves to the newest 6.18.x tag).
  Built with `BRANCH=current` (`KERNEL_MAJOR_MINOR=6.18`).
- **Patches**, applied to pristine `v6.18.35` in this order:
  1. `patch/kernel/archive/sunxi-6.18/` — driven by `series.conf` (**517 applied
     entries**; most sourced from megi's `orange-pi-6.18` branch). Per-subdir
     applied counts: `patches.megous` 282, `patches.armbian` 155, `patches.drm`
     43, `patches.backports` 25, `patches.media` 6 (plus `dt_*`/`overlay_*` files).
     The overwhelming majority target **unrelated boards/SoCs**.
  2. `userpatches/kernel/archive/sunxi-6.18/` — the operator's `0099` (DE33 NV12
     VI plane) and `0100` (Cedrus prefer-linear-NV12).
  3. `patch/misc/wireless-uwe5622/` — the UWE5622 WiFi/BT driver, applied by the
     **driver harness** (`drivers_network.sh:driver_uwe5622`), **version-gated** so
     only a subset hits 6.18.
- **Config:** `config/kernel/linux-sunxi64-current.config` (69 KB) — the ancestor
  of the repo's captured `board/orangepi/zero2w/linux.config` (currently 9,667
  lines, the full sunxi64 config).

Key structural facts that shape the design:

- The board DTS `sun50i-h618-orangepi-zero2w.dts` is **already in mainline
  6.18.35** (with its `hdmi-connector`/`&hdmi` nodes); Armbian only adds a small
  `patches.armbian/0302-…-add-emac-sound` tweak. We do **not** reconstruct the board
  DTS — only the SoC-level DE33/HDMI **display-pipeline** nodes (added to
  `sun50i-h616.dtsi` by the `patches.drm` DT patches, e.g. `0041`/`0042`).
- The display core is a coherent **43-patch block** (`patches.drm/0001…0043`,
  sun4i → DE33 refactor), but it is authored to apply **on top of megi's tree**, so
  it needs a (small, to-be-determined) set of `patches.megous`/`patches.armbian`
  prerequisites.

## Goal

Build the kernel entirely within `sbc-groundstations`:

- Buildroot fetches **pristine mainline 6.18.35** from kernel.org and applies a
  **curated, in-repo patch subset** (display + Cedrus + DTS + UWE5622 + the two
  NV12 userpatches) — no pre-patched tarball.
- The kernel `.config` is **trimmed to the modules/features the board actually
  uses** (display, video decode, WiFi/SDIO, storage, USB host+gadget, platform),
  ground-truthed from the running board rather than guessed.
- A fresh clone builds the board with `DEFCONFIG=orangepi_zero2w_defconfig
  ./build.sh` and **no Armbian prerequisite**. The Armbian tree is needed only
  *once*, to extract the patch subset, and is thereafter not a build dependency.

## Non-goals (YAGNI)

- **No** UWE5622-as-Buildroot-package — it stays an in-tree kernel patch/module.
- **No** vendoring of the full ~517-entry series — curated subset only.
- **No** kernel version bump — stays pinned at 6.18.35.
- **No** changes to U-Boot, ATF, the video/ffmpeg path, or the wfb stack.
- **No** arm32 DTs / DT overlays for other boards.
- Other defconfigs (radxa/runcam/emax/bonnet) are untouched.

## Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Source | `BR2_LINUX_KERNEL_CUSTOM_VERSION=y` + `..._CUSTOM_VERSION_VALUE="6.18.35"` (kernel.org) | pristine mainline, self-contained |
| Patch representation | **Curated minimal subset**, frozen in-repo + manifest | cleanest end state; matches "required only" intent |
| Subset derivation | **Empirical** (trial-apply, close gaps via `series.conf`) | the prerequisite tail can't be declared a priori |
| UWE5622 | **Kernel patch** (version-correct subset), in-tree `=m` | proven on hardware, consistent with subset choice |
| Config trim | `localmodconfig` from live board + manual built-in prune | ground truth, not guesswork |
| Verification | board + SSH + quick reflash; boot-test every change | only safe way to validate cuts |

## Architecture

### §1 — Kernel source (defconfig)

```diff
- BR2_LINUX_KERNEL_CUSTOM_TARBALL=y
- BR2_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION="file://${BR2_EXTERNAL_OPENIPC_SBC_GS_PATH}/.opi-artifacts/linux-6.18.35-opi-sunxi.tar.gz"
+ BR2_LINUX_KERNEL_CUSTOM_VERSION=y
+ BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="6.18.35"
+ BR2_GLOBAL_PATCH_DIR="${BR2_EXTERNAL_OPENIPC_SBC_GS_PATH}/board/orangepi/zero2w/patches"
```

Unchanged: `BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG` + `…_CUSTOM_CONFIG_FILE` (now the
trimmed `linux.config`), `BR2_LINUX_KERNEL_INTREE_DTS_NAME=
"allwinner/sun50i-h618-orangepi-zero2w"`, `DTB_KEEP_DIRNAME`, `INSTALL_TARGET`.

Buildroot downloads `linux-6.18.35.tar.xz` from kernel.org and applies
`board/orangepi/zero2w/patches/linux/*.patch` in **alphanumeric order** — so subset
files are numbered to preserve the Armbian `series.conf` application order.
Reproducibility comes from the pinned `CUSTOM_VERSION` string; note Buildroot has
**no upstream hash** for a custom kernel version (it emits a "no hash file" warning
and proceeds — the global patch dir does not supply package hashes), so the
download is version-pinned but not checksum-verified unless we patch the kernel
package's own `linux.hash` (deferred — see §6).

### §2 — Curated patch subset (the crux)

The subset is **derived empirically once, then frozen** in the repo. It lives at
`board/orangepi/zero2w/patches/linux/` as ordered, numbered `.patch` files, plus a
checked-in manifest `board/orangepi/zero2w/kernel-patches.list` recording exactly
which Armbian patches were selected (path + order), so the set is auditable and
re-derivable without spelunking.

**Derivation procedure** (encoded in `scripts/extract-kernel-patches.sh`, run
against the Armbian tree):

1. **Seed set** (the obviously board-relevant patches):
   - `patches.drm/0001…0043` (DE33 display core + H616 HDMI PHY + display-pipeline DT)
   - `patches.media/*` (Cedrus, 6)
   - `patches.armbian/0302-…-orangepi-zero2w-add-emac-sound`
   - UWE5622 set as selected by `driver_uwe5622()` for v6.18.35 — **indicatively**
     `uwe5622-allwinner-v6.3.patch` (13 MB base), `-bugfix-v6.3`,
     `-v6.3-compilation-fix`, `uwe5622-v6.4-post`, `uwe5622-v6.1`,
     `uwe5622-park-link-v6.1-post`, `uwe5622-v6.6-fix-tty-sdio`, `uwe5622-warnings`
     (and likely `uwe5622-v6.18.patch` / `wireless-uwe5622-Fix-missing-prototypes`
     from the `≥6.x`/`sun*` tails of the function), **plus** the
     `drivers/net/wireless/Makefile` append `obj-$(CONFIG_SPARD_WLAN_SUPPORT) +=
     uwe5622/` (captured as a generated patch). The extraction script **replays the
     harness version gates verbatim** rather than relying on this list, so the set
     is correct by construction; the list above is illustrative.
   - `0099-de33-enable-nv12-vi-plane`, `0100-cedrus-prefer-linear-nv12`
2. **Close the dependency gap:** apply the seed on pristine 6.18.35; on each failed
   hunk, consult `series.conf` to pull in the prerequisite
   `patches.megous`/`patches.armbian` patch (in series order) and retry, until the
   set applies and the kernel builds. Candidate prerequisites already spotted:
   `patches.megous/anx-6.18` dw-hdmi HPD patches, `patches.megous/fixes-6.18`
   sun4i reverts. (Optional, decide during impl: the `hdmi-audio-6.18` set, only
   if HDMI audio is required.)
3. **Freeze + manifest:** commit the ordered subset and `kernel-patches.list`.

Authoritative success criterion is **not** "applies cleanly" but **boots + display
+ WiFi + video work on the board** (§4).

### §3 — Trimmed kernel config ("required modules only")

Ground-truthed from the running validated board, not guessed:

1. Capture `zcat /proc/config.gz` (known-good baseline) and `lsmod` over SSH.
2. `make LSMOD=<lsmod.txt> localmodconfig` → drops every `=m` not actually loaded.
3. Manually prune unneeded **built-ins**: other SoC families/arches, unused
   filesystems, debug/tracing — **keeping** the Allwinner H616/H618 platform
   (pinctrl/clk/CCU/regulators/CMA), DE33 DRM (`DRM_SUN4I*`, `DRM_SUN8I_*`,
   `DRM_SUN50I_PLANES`, `DRM_SUN8I_DW_HDMI`), Cedrus (`VIDEO_SUNXI`,
   v4l2-request/Hantro-Cedrus), `MMC_SUNXI`, USB host + gadget (OTG), squashfs, and
   the wireless stack (`cfg80211`/`mac80211`, `AW_WIFI_DEVICE_UWE5622=y`,
   `WLAN_UWE5622=m`).
4. **Built-in vs module policy:** rootfs-critical (MMC, squashfs, zstd) = `=y` (so
   no initramfs is required); out-of-tree drivers (uwe5622, rtl88x2*) = `=m`;
   display/Cedrus = `=y`. **Confirm during impl** that the current boot path has no
   initramfs (check `board/orangepi/zero2w/boot.cmd` + `genimage.cfg`); if it does,
   the policy holds anyway but document it.
5. The result replaces `board/orangepi/zero2w/linux.config`. Each trimming round is
   boot-tested (§4); never trim without a passing boot.

### §4 — Verification loop

`build → flash → SSH` each iteration, with concrete acceptance gates mapped to the
board's real features:

- boots to login over serial/SSH; `lsmod` matches intent (no surprise modules)
- `wlan0` hotspot up: `uwe5622`/`sprdwl_ng` bound, `dnsmasq` serving, `iw dev` /
  `ip link` OK; BT (`sprdbt_tty`) present
- HDMI/DE33 plane works: DRM device + plane via `modetest`, or the citruspilot
  player rendering
- Cedrus H.265 HW decode works through the FPV player path (`udp:5600`)
- DVR storage partition mounts; USB gadget mode (`Left`-button) still works

### §5 — Repo layout, tooling & cleanup

```
board/orangepi/zero2w/
  patches/linux/                 # frozen, numbered curated subset (.patch) + linux.hash
  kernel-patches.list            # manifest: selected Armbian patches + order
  linux.config                   # trimmed (replaces the 9,667-line full config)
scripts/
  extract-kernel-patches.sh      # one-time, needs the Armbian tree; emits patches/linux + manifest
```

Cleanup:
- **Delete** `scripts/prepare-opi-artifacts.sh` (ffmpeg already moved to
  `package/ffmpeg-v4l2request`, so its remaining kernel half is the only user — dead
  once §1 lands).
- Remove the `.opi-artifacts/linux-6.18.35-opi-sunxi.tar.gz` input and its
  `.gitignore` entry (the dir may still be created by other tooling — verify before
  removing the ignore line).
- **README:** add Orange Pi Zero 2W to "Supported GS Hardware"; document the build
  as plain `DEFCONFIG=orangepi_zero2w_defconfig ./build.sh` with **no Armbian
  prerequisite**. This closes the documentation gap identified earlier in this work.

### §6 — Risks & mitigations

- **Incomplete dependency closure** (missing a `patches.megous` prerequisite) →
  empirical apply + mandatory boot test; the current working `linux.config` and the
  existing snapshot tarball remain the fallback baseline until the in-house build is
  proven.
- **Over-trimming** breaks boot or a feature → `lsmod` ground truth + per-round
  boot test; bisect by re-enabling.
- **kernel.org fetch not checksum-verified** (custom version → no Buildroot hash) →
  acceptable (version-pinned; 6.18.35 is a released stable Armbian already builds);
  optionally append a hash to the kernel package's `linux.hash` if verification is
  wanted.
- **Subset drifts from reality over time** → the manifest + extraction script make
  re-derivation mechanical; the Armbian tree is the (optional) re-derivation source.

## Acceptance criteria (definition of done)

1. With **no `.opi-artifacts/` and no Armbian tree present**, a clean
   `DEFCONFIG=orangepi_zero2w_defconfig ./build.sh` produces a bootable
   `orangepi_zero2w_sdcard.img`.
2. The image boots on hardware and passes all §4 gates (display, WiFi hotspot,
   Cedrus video, storage, USB gadget).
3. `linux.config` is materially smaller than the 9,667-line baseline and contains
   only board-relevant subsystems; `lsmod` shows no unexpected modules.
4. `board/orangepi/zero2w/patches/linux/` + `kernel-patches.list` are committed;
   `scripts/extract-kernel-patches.sh` reproduces them from the Armbian tree.
5. `scripts/prepare-opi-artifacts.sh` and the `.opi-artifacts` kernel input are
   gone; README documents the self-contained build.

## To confirm during implementation

- Exact `patches.megous`/`patches.armbian` prerequisite set for the DRM block
  (empirical).
- Whether the boot path uses an initramfs (drives the `=y` vs `=m` policy detail).
- Whether HDMI audio is in scope (adds the `hdmi-audio-6.18` patch set if so).
- Whether to add a `linux.hash` entry for 6.18.35 (vs. accepting the no-hash warning).
