# Orange Pi Zero 2W (Allwinner H618) board support — design

**Date:** 2026-06-17
**Repos touched:** `sbc-groundstations` (new sunxi platform + board-aware wiring)
**Companion work (out of scope here):** the H618 live video player, built separately
by the operator (uses the kernel video path + ffmpeg this spec provides).

## Context

The image builder is a Buildroot 2025.08 external tree. Today **every supported
board is Rockchip RK3566**: `radxa_zero3`, `runcam_wifilink`, `emax_wyvern-link`,
`openipc_bonnet` all share one platform definition (`board/radxa/zero3/`) and a
single video player, `pixelpilot` (Rockchip MPP/RGA).

We want to add the **Orange Pi Zero 2W** (Allwinner **H618**, Cortex-A53) — the
project's **first non-Rockchip platform**. The operator already has hardware
video decode working on this board under Armbian (kernel `6.18.35-current-sunxi64`)
via two Cedrus/DE33 kernel patches and a custom direct-to-plane player. That work
lives in `~/Projects/h618-mainline-video/` (patches `0099`, `0100`; `drmvid.c`).

`pixelpilot` cannot be reused (it is Rockchip-MPP-bound). The H618 video path is
Cedrus (`v4l2-request`) HW decode → DRM-PRIME NV12 → direct scanout on the DE33
overlay plane.

## Goal (v1)

A small, radxa-sized Buildroot squashfs image (`orangepi_zero2w_sdcard.img`) that:

- boots the OPi Zero 2W from microSD (HDMI, MMC, USB),
- brings up **onboard UWE5622 WiFi** (`wlan0`, for hotspot / config AP),
- carries the wfb-ng link on a USB RTL adapter (as today),
- provides the **kernel video path** (Cedrus + DE33 NV12 overlay, via patches
  `0099`/`0100`) and an **ffmpeg built with `--enable-v4l2-request`** that the
  operator's player links against,
- brings up the wfb link via the **stock `wifibroadcast-ng` init** (no `fpvd` in
  v1), which forwards video to **UDP:5600** for the operator's player.

## Scope

**In scope:** new sunxi platform (defconfig + `board/orangepi/zero2w/`), native
mainline 6.18 kernel build with the video + UWE5622 patches, trimmed kernel
config, sunxi u-boot + ATF, sunxi image/boot assembly, `ffmpeg`
with v4l2-request, board-aware build wiring, the stock `wifibroadcast-ng` wfb link
(USB RTL adapter → video on UDP:5600).

**Out of scope (operator is building / later specs):** the H618 live-stream
player binary and its RTP:5600 ingest; the **`fpvd` GS supervisor** (this board
uses the stock `wifibroadcast-ng` orchestration in v1); OSD (msposd); DVR;
adaptive-link; web UI (openipc-gs-web / go2rtc); onboard **Bluetooth**
(`sprdbt_tty`). The image exposes the integration contract (working kernel video
path + ffmpeg + video on UDP:5600) so the player drops in without further board
changes.

## Key decisions (from brainstorming)

1. **Kernel = native mainline in Buildroot** (not prebuilt-Armbian, not
   Armbian-source). Validated drift: the entire video path is stock-mainline
   built-ins (`VIDEO_SUNXI_CEDRUS=y`, `DRM_SUN4I=y`, `DRM_SUN8I_MIXER=y`,
   `DMABUF_HEAPS=y`, `V4L_MEM2MEM_DRIVERS=y`); only patches `0099`/`0100` are
   needed on top. The live Armbian config is a distro monster (2173 built-ins +
   2547 modules) — we build a **trimmed** config instead, for a radxa-sized image.
2. **Onboard WiFi = W1, replay Armbian's UWE5622 patch series in-tree.** There is
   **no upstream repo**: Armbian adds the driver via a 13 MB base patch
   (`uwe5622-allwinner-v6.3.patch`, lifted from the Allwinner/UNISOC "longan" BSP)
   plus ~20 version-specific patches, including `uwe5622-v6.18.patch` matching our
   kernel. We vendor the needed subset into `board/orangepi/zero2w/linux-patches/`
   and enable the config symbols — the driver builds in-tree exactly as on the
   validated board. (W2, an out-of-tree kernel-module package, was rejected: the
   vendor Makefiles would likely need `M=` build fixups — extra risk for no gain.)
3. **Video userspace = ffmpeg with `--enable-v4l2-request` only.** The player
   itself is the operator's separate work. No new player package in this spec.

## Findings (why this shape)

- **All four existing boards are RK3566** and share `board/radxa/zero3/`; differ
  only by overlay + GPIO pins + a few package toggles. So sunxi support is purely
  **additive** — a parallel platform, no change to Rockchip boards.
- **Validated against the live board** (`root@192.168.10.91`, passwordless SSH):
  - Video symbols all present and built-in (above).
  - Onboard WiFi is out-of-tree UWE5622: modules `sprdwl_ng` + `sunxi_addr`
    (+ `sprdbt_tty` for BT), `intree: Y`, binding SDIO on `mmc@4021000`
    (`cap-sdio-irq`, `non-removable`, `mmc-pwrseq`); DT has `wifi-pwrseq` and a
    `vcc-wifi-io` regulator. Firmware: `/lib/firmware/uwe5622/wcnmodem.bin`,
    `wcnmodem-38222.bin`, `wifi_2355b001_1ant.ini`, plus a
    `/lib/firmware/wcnmodem.bin` symlink.
  - DTB in use: `allwinner/sun50i-h618-orangepi-zero2w.dtb`. Boot is Armbian
    extlinux/boot.scr; bootargs include `cma=256M`.
- **Video ingest contract:** the player receives **RTP/H.265 on UDP:5600**
  (the same `rtpPort:5600`/`codec:h265` the Rockchip stack uses). In v1 the stock
  `wifibroadcast-ng` `S98wifibroadcast` init configures `wfb_rx` to forward the
  video to `127.0.0.1:5600` (the pre-fpvd OpenIPC path); the operator's player
  reads that port.
- **Image/boot is Rockchip-shaped:** `board/common/genimage.cfg` writes
  `u-boot-rockchip.bin` at 32K on GPT; `board/common/boot.cmd` is the Rockchip
  eMMC-flasher. sunxi needs MBR + `u-boot-sunxi-with-spl.bin` at 8K + a normal-boot
  `boot.cmd`. `BR2_ROOTFS_POST_SCRIPT_ARGS` already passes the genimage cfg path
  per-defconfig, so the image layout is board-selectable; `gen-boot-scr.sh`
  hardcodes `board/common/boot.cmd` and must be generalized.
- **Buildroot `ffmpeg` exists** but its `Config.in` exposes no v4l2-request toggle
  → enabling it needs a package override/patch. ffmpeg is not currently used by
  any package in the tree (pixelpilot uses gstreamer), so adding it is isolated.
- **`fpvd` is not installed on this board in v1** (operator's call), so its
  hard-coded `pixelpilot` dependency is moot — we simply leave `BR2_PACKAGE_FPVD`
  off and do not touch `fpvd.mk`. The wfb link is brought up by
  `wifibroadcast-ng`'s stock `S98wifibroadcast` init instead.

## Changes

### 1. New board platform — `board/orangepi/zero2w/`

```
board/orangepi/zero2w/
  overlay/                 # board-specific rootfs overlay (incl. fpvd config.json variant)
  linux.config             # trimmed kernel config (seeded from live board, savedefconfig)
  linux.fragment           # must-haves + UWE5622 config symbols (see §3)
  linux-patches/           # 0099, 0100 (video) + UWE5622 patch subset + DTS wifi patch (if needed)
  genimage.cfg             # sunxi image layout (MBR, SPL@8K)
  boot.cmd                 # normal sunxi boot (load Image+DTB, set bootargs, booti)
```

### 2. New defconfig — `configs/orangepi_zero2w_defconfig`

Derived from `radxa_zero3_defconfig`, with these platform changes:

- `BR2_aarch64=y`, `BR2_cortex_a53=y` (H618 is A53; radxa is A55).
- **Kernel:** `BR2_LINUX_KERNEL_CUSTOM_TARBALL` mainline **6.18.x** (match 6.18.35);
  `BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG` → `board/orangepi/zero2w/linux.config`;
  `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES` → `board/orangepi/zero2w/linux.fragment`;
  `BR2_LINUX_KERNEL_PATCH` → `board/orangepi/zero2w/linux-patches`;
  `BR2_LINUX_KERNEL_INTREE_DTS_NAME="allwinner/sun50i-h618-orangepi-zero2w"`.
- **u-boot:** `BR2_TARGET_UBOOT_BOARD_DEFCONFIG="orangepi_zero2w"`;
  ATF via `BR2_TARGET_ARM_TRUSTED_FIRMWARE` with `PLAT=sun50i_h616` providing
  `bl31.bin`; output `u-boot-sunxi-with-spl.bin`. Drop all Rockchip rkbin/rkdeveloptool.
- **Image:** `BR2_ROOTFS_POST_SCRIPT_ARGS="-c .../board/orangepi/zero2w/genimage.cfg"`.
- **Overlay:** swap the radxa overlay for `board/orangepi/zero2w/overlay`.
- **Packages — add:** `BR2_PACKAGE_FFMPEG=y` (+ v4l2-request, §4). UWE5622
  firmware ships via the board overlay, not a package (§3).
- **Packages — drop (Rockchip-only / unneeded for direct-to-plane):**
  `pixelpilot`, `rockchip-mpp`, `librga`, `mali-driver-custom`, `rockchip-rkbin`,
  `rkdeveloptool`, and candidate-for-drop `gstreamer1`/`mesa3d`/`panfrost`
  (revisit if the operator's player needs them). Also **`fpvd` off in v1**
  (`BR2_PACKAGE_FPVD` unset). Keep the wfb link stack (`wifibroadcast-ng`,
  `wfb-server`) + RTL drivers, squashfs, dnsmasq/wpa_supplicant (hotspot), python.
- GPIO factory-reset / gadget pins: set to OPi Zero 2W header pins (TBD from board).

### 3. Onboard WiFi — UWE5622 (W1, in-tree)

- **Patches** in `board/orangepi/zero2w/linux-patches/`: the version≥6.18 + sunxi
  subset Armbian applies, in order — base `uwe5622-allwinner-v6.3.patch`,
  `-bugfix-v6.3`, `-v6.3-compilation-fix`, `-v6.4-post`, `-warnings`,
  the Makefile-append (`obj-$(CONFIG_SPARD_WLAN_SUPPORT) += uwe5622/`),
  `-v6.1` + `-park-link-v6.1-post`, `-v6.6-fix-tty-sdio`,
  `-fix-setting-mac-address-for-netdev` (sunxi), `Fix-compilation-with-6.7-kernel`,
  `reduce-system-load`, `-v6.9`, `-v6.11`, `-fix-spanning-writes`,
  `-fix-timer-api-changes-for-6.15-only-sunxi`, `-v6.16`, `-v6.17`, `-v6.18`,
  `Fix-missing-prototypes`. Source: `~/h618-kernel-work/armbian-build/patch/misc/wireless-uwe5622/`.
- **Config** in `linux.fragment`: `CONFIG_SPARD_WLAN_SUPPORT=y`,
  `CONFIG_WLAN_UWE5622=m`, `CONFIG_SPRDWL_NG=m`, `CONFIG_UNISOC_WIFI_PS=y`
  (plus `CONFIG_STAGING=y`, `CONFIG_CFG80211=m`, `CONFIG_RFKILL=m`).
- **DTS:** confirm mainline `sun50i-h618-orangepi-zero2w.dts` carries the SDIO WiFi
  nodes (`mmc@4021000` sdio config, `wifi-pwrseq`, `vcc-wifi-io`). If not, add a
  small DTS patch in `linux-patches/` (verify by diffing the Armbian DTB source vs
  mainline). **Open verification item.**
- **Firmware:** ship via the board rootfs overlay —
  `board/orangepi/zero2w/overlay/lib/firmware/uwe5622/` (snapshot the board's
  `wcnmodem.bin`, `wcnmodem-38222.bin`, `wifi_2355b001_1ant.ini`) plus the
  `/lib/firmware/wcnmodem.bin` symlink. No new package.

### 4. ffmpeg with v4l2-request

- Enable `BR2_PACKAGE_FFMPEG=y` and build with `--enable-v4l2-request`
  (requires libdrm, already in the tree). Buildroot's ffmpeg `Config.in` lacks the
  toggle → append it from the external tree: `FFMPEG_CONF_OPTS += --enable-v4l2-request`
  in `external.mk`. If the v4l2-request hwaccel needs source changes on 6.18
  headers, add a patch via `BR2_GLOBAL_PATCH_DIR`. **Risk item** — prototype
  against the live board's ffmpeg first.
- Provides `AV_HWDEVICE_TYPE_V4L2REQUEST` + DRM-PRIME output for the operator's player.

### 5. Board-aware build wiring

- **`external.mk`:** guard the `include board/radxa/zero3/flash.mk` so it is only
  pulled for Rockchip (`BR2_PACKAGE_HOST_RKDEVELOPTOOL`) — sunxi has no rkdeveloptool.
- **`build.sh`:** the artifact step hardcodes `cp u-boot-rockchip.bin u-boot.bin`
  and a Rockchip artifact list. Make it board-aware: sunxi →
  `u-boot-sunxi-with-spl.bin`; emit `orangepi_zero2w_sdcard.img` + `_boot.scr` +
  the `.tar.gz`/md5 bundle as for other boards.
- **`gen-boot-scr.sh`:** prefer a board-specific `boot.cmd`
  (`board/<vendor>/<board>/boot.cmd`) when present, else `board/common/boot.cmd`.

### 6. wfb link (no fpvd in v1)

- Do **not** enable `fpvd` on this board for v1; do not modify `fpvd.mk`. Enable
  the stock wfb link stack (`wifibroadcast-ng` + `wfb-server`) + USB RTL drivers.
  `wifibroadcast-ng`'s `S98wifibroadcast` brings up the link and forwards video to
  `127.0.0.1:5600`. The operator's player consumes that port and handles display;
  its launcher (free console / unbind fbcon / claim `/dev/video0`) ships with the
  player, not this board. Porting `fpvd` to sunxi is a follow-up spec.

## Data flow (v1 substrate)

```
USB RTL adapter ──(wfb-ng)──> wifibroadcast-ng S98 (wfb_rx) ──RTP/H.265 127.0.0.1:5600──> [operator's player]
                                                                            │  (links ffmpeg
                                                                            │   v4l2-request)
                                            Cedrus HW decode ──DRM-PRIME NV12──> DE33 overlay plane (HDMI)
onboard UWE5622 wlan0 ── hotspot / config AP (dnsmasq + wpa_supplicant)
```

## Risks (ordered) & mitigations

1. **ffmpeg v4l2-request in Buildroot** — no stock toggle; hwaccel may need a
   patch for 6.18. *Mitigate:* prototype the build, test decode on the live board.
2. **UWE5622 against mainline 6.18 + DTS** — patch series must apply on pure
   mainline (not Armbian-patched) source; DTS may lack SDIO/pwrseq nodes.
   *Mitigate:* the `-v6.18` patch targets exactly this version; diff Armbian DTB vs
   mainline; bring up `wlan0` on a hand-built kernel before trusting Buildroot.
3. **Mainline-vs-Armbian board gaps** (HDMI modes, USB, thermal). *Mitigate:* OPi
   Zero 2W is well-supported mainline; validate boot + HDMI early.
4. **sunxi u-boot + ATF + image offsets** (SPL@8K, MBR). *Mitigate:* standard
   Buildroot sunxi pattern; verify SD boots before integrating the rest.

## Testing strategy

Stage incrementally against the live board over SSH (`root@192.168.10.91`) before
trusting the full image:

1. Build the trimmed mainline 6.18 kernel + `0099`/`0100` + UWE5622 patches;
   boot it on the board (replace Armbian's kernel), confirm HDMI, `wlan0` up via
   uwe5622, Cedrus decode (`v4l2-ctl`/ffmpeg), DE33 NV12 plane (`modetest -p`).
2. Build ffmpeg with v4l2-request; confirm HW decode through it.
3. Full Buildroot build of `orangepi_zero2w_defconfig`; flash
   `orangepi_zero2w_sdcard.img` to microSD; confirm boot + WiFi + the stock
   `wifibroadcast-ng` wfb link forwarding to UDP:5600, and (once the operator's
   player lands) live video to screen.

## Follow-up specs (post-v1)

Each its own spec → plan → implementation cycle: the H618 player; the **`fpvd` GS
supervisor ported to sunxi**; OSD (msposd); DVR; adaptive-link; web UI / go2rtc;
onboard Bluetooth.
