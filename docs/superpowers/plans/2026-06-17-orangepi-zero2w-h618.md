# Orange Pi Zero 2W (H618) board support — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Orange Pi Zero 2W (Allwinner H618) as the first non-Rockchip platform in this Buildroot image builder, with onboard UWE5622 WiFi, the Cedrus/DE33 hardware video path, and ffmpeg(`--enable-v4l2-request`) — leaving the live-stream player to the operator.

**Architecture:** A parallel sunxi platform under `board/orangepi/zero2w/`, selected by a new `configs/orangepi_zero2w_defconfig`. Native mainline 6.18 kernel built in Buildroot + the operator's `0099`/`0100` video patches + the Armbian UWE5622 patch series (in-tree, "W1"); sunxi u-boot + ATF; MBR image with SPL@8K; SD-boot. Rockchip boards are untouched.

**Tech Stack:** Buildroot 2025.08, mainline Linux 6.18.x (sunxi), U-Boot `orangepi_zero2w` + ARM Trusted Firmware `sun50i_h616`, genimage, FFmpeg with V4L2-request, Cedrus + sun4i/DE33 DRM.

## How tasks are validated (read first)

This is infra, not application code — there are no pytest units. Each task's "test" is: **build the artifact, deploy/flash to the live board, and observe a specific runtime fact.** The reference board is the operator's working Armbian system at `root@192.168.10.91` (passwordless SSH). Rules:

- **Flash to a SECOND microSD** — keep the Armbian board intact as the known-good reference for diffing (`/proc/config.gz`, DTBs, `/lib/firmware`).
- Pre-WiFi access to the Buildroot image is via **serial console** (`console=ttyS0,115200`) and **USB-OTG gadget networking** (`192.168.5.1`, provided by `board/common`). Onboard WiFi comes up in Task 4.
- "Expected: FAIL/PASS" lines describe the **observed board state before vs. after** the change. When a step says "diff against the reference board," that means SSH to `192.168.10.91`.
- Each task ends with a commit on branch `feat/orangepi-zero2w`.

Reference inputs already gathered (do not re-derive):
- Live kernel config: `/proc/config.gz` on the board (video path is all built-in mainline symbols).
- UWE5622 patch series: `~/h618-kernel-work/armbian-build/patch/misc/wireless-uwe5622/`.
- Video patches: `~/Projects/h618-mainline-video/patches/0099-*.patch`, `0100-*.patch`.
- Firmware: board `/lib/firmware/uwe5622/{wcnmodem.bin,wcnmodem-38222.bin,wifi_2355b001_1ant.ini}` + symlink `/lib/firmware/wcnmodem.bin`.
- Spec: `docs/superpowers/specs/2026-06-17-orangepi-zero2w-h618-design.md`.

## Global Constraints

> **REVISION (mid-execution, kernel strategy pivot — Option 1).** Mainline 6.18.35 has **no** H616/H618 DE33 display support (verified against kernel.org: `sun50i-h616.dtsi` has no display nodes; `sun8i_vi_layer.c` has no `de33` array, so patch `0099` won't apply). DE33 + the board's HDMI/WiFi DTS + the uwe5622 driver are all carried by **Armbian** patches. So the kernel is now built from a **pinned snapshot of the Armbian-patched 6.18.35 source** (which already contains DE33, the operator's `0099`/`0100`, the uwe5622 driver, and the HDMI+WiFi DTS), not pristine mainline. This **reverts Task 3** (patches already in the snapshot) and **collapses Task 4** to firmware-only.

- **Kernel:** built in Buildroot from a **pinned tarball snapshot of the Armbian-patched 6.18.35 source** at `~/h618-kernel-work/opi-kernel-snapshot/linux-6.18.35-opi-sunxi.tar.gz` (via `BR2_LINUX_KERNEL_CUSTOM_TARBALL`). Config = the captured live-board `.config` (`board/orangepi/zero2w/linux.config`), which now matches the snapshot source exactly. **No kernel patches** — `0099`/`0100`/uwe5622/DTS are all in the snapshot.
- **Onboard WiFi:** the uwe5622 **driver and the SDIO WiFi DTS are already in the kernel snapshot**, and the captured `.config` enables `CONFIG_WLAN_UWE5622=m`/`CONFIG_SPRDWL_NG=m`. The board only ships the **firmware** (`/lib/firmware/uwe5622/*` + `wcnmodem.bin` symlink) via the rootfs overlay + a `modules-load.d` entry. No patches, no DTS work, no kernel-module package.
- **Video userspace = `ffmpeg --enable-v4l2-request` only.** No new player package; the player is the operator's separate work. Leave the fpvd player hook as a placeholder.
- **Image:** MBR partition table, `u-boot-sunxi-with-spl.bin` at **8K**, squashfs rootfs, **SD-boot only** (no eMMC flasher).
- **Additive only:** do not change any Rockchip board's defconfig or `board/radxa/zero3/`. After every task, `radxa_zero3` must still build (smoke-check in Task 1, then trust).
- **Target:** `BR2_aarch64=y`, `BR2_cortex_a53=y` (H618 is Cortex-A53).
- Branch: `feat/orangepi-zero2w`. Commit per task.

---

### Task 1: Sunxi platform scaffold — minimal bootable image

Stand up the new platform end-to-end using the **live board's captured kernel config** (guaranteed to drive this exact hardware and to mount the squashfs root), so the first image boots to a login prompt. This folds in the old Task 2: arm64 has no `sunxi_defconfig`, so there is no useful "stock kernel" intermediate, and the captured config is the known-good baseline.

**Files:**
- Create: `configs/orangepi_zero2w_defconfig`
- Create: `board/orangepi/zero2w/linux.config` (captured from the live board via SSH)
- Create: `board/orangepi/zero2w/genimage.cfg`
- Create: `board/orangepi/zero2w/boot.cmd`
- Create: `board/orangepi/zero2w/uboot.fragment`
- Create: `board/orangepi/zero2w/overlay/.empty` (placeholder so the overlay dir exists)
- Modify: `external.mk` (guard the Rockchip flash include)
- Modify: `build.sh` (board-aware u-boot artifact name)
- Modify: `board/common/gen-boot-scr.sh` (prefer board-specific `boot.cmd`)

**Interfaces:**
- Produces: defconfig name `orangepi_zero2w_defconfig`; board dir `board/orangepi/zero2w/`; image artifact `orangepi_zero2w_sdcard.img` + `orangepi_zero2w_boot.scr`; u-boot output `u-boot-sunxi-with-spl.bin`. Later tasks override only the kernel-related defconfig keys and add overlay files / patches.

- [ ] **Step 1: Write `board/orangepi/zero2w/genimage.cfg`** (sunxi MBR layout, SPL@8K)

```
# Orange Pi Zero 2W SD image (Allwinner sunxi)
image sdcard.img {
	hdimage {
		partition-table-type = "mbr"
	}

	# sunxi SPL + U-Boot, written raw at 8 KiB (not in the partition table)
	partition spl {
		in-partition-table = "false"
		image = "u-boot-sunxi-with-spl.bin"
		offset = 8K
	}

	# rootfs starts well past the U-Boot reservation
	partition rootfs {
		partition-type = 0x83
		image = "rootfs.squashfs"
		offset = 16M
		bootable = "true"
	}
}
```

- [ ] **Step 2: Write `board/orangepi/zero2w/boot.cmd`** (normal sunxi boot: load kernel+DTB from the squashfs rootfs and boot)

```
# Orange Pi Zero 2W normal boot. Generated to boot.scr by gen-boot-scr.sh.
# Boots the kernel + DTB from the squashfs rootfs partition (mmc 0:1).
setenv bootargs console=ttyS0,115200 console=tty1 consoleblank=0 \
	root=/dev/mmcblk0p1 rootfstype=squashfs ro rootwait cma=256M loglevel=7

setenv fdtfile allwinner/sun50i-h618-orangepi-zero2w.dtb

echo "Loading kernel and DTB from squashfs rootfs (mmc 0:1)..."
load mmc 0:1 ${kernel_addr_r} /boot/Image
load mmc 0:1 ${fdt_addr_r} /boot/dtb/${fdtfile}
fdt addr ${fdt_addr_r}
booti ${kernel_addr_r} - ${fdt_addr_r}
```

Note: requires squashfs read support in U-Boot (added via the uboot fragment in Step 4). Partition/path specifics are bring-up assumptions — Step 11 confirms or adjusts them against actual U-Boot behavior.

- [ ] **Step 3: Generalize `board/common/gen-boot-scr.sh` to prefer a board-specific `boot.cmd`**

Replace the `BOOT_CMD` resolution block:

```bash
# Locate boot.cmd via BR2_EXTERNAL or BR2_EXTERNAL_OPENIPC_SBC_GS_PATH
_EXT="${BR2_EXTERNAL:-${BR2_EXTERNAL_OPENIPC_SBC_GS_PATH}}"
: "${_EXT:?Neither BR2_EXTERNAL nor BR2_EXTERNAL_OPENIPC_SBC_GS_PATH is set}"
BOOT_CMD="${_EXT}/board/common/boot.cmd"
```

with:

```bash
# Locate boot.cmd via BR2_EXTERNAL or BR2_EXTERNAL_OPENIPC_SBC_GS_PATH.
# Prefer a board-specific boot.cmd (board/<vendor>/<board>/boot.cmd) when present,
# derived from the defconfig name, else fall back to the common (Rockchip) one.
_EXT="${BR2_EXTERNAL:-${BR2_EXTERNAL_OPENIPC_SBC_GS_PATH}}"
: "${_EXT:?Neither BR2_EXTERNAL nor BR2_EXTERNAL_OPENIPC_SBC_GS_PATH is set}"
case "$PLATFORM" in
	orangepi_zero2w) BOOT_CMD="${_EXT}/board/orangepi/zero2w/boot.cmd" ;;
	*)               BOOT_CMD="${_EXT}/board/common/boot.cmd" ;;
esac
```

(`$PLATFORM` is already computed earlier in the script.)

- [ ] **Step 4: Write `configs/orangepi_zero2w_defconfig`**

Start from `radxa_zero3_defconfig` and apply the platform changes. The kernel uses the live board's captured config (`board/orangepi/zero2w/linux.config`), captured first via `ssh -o BatchMode=yes root@192.168.10.91 'zcat /proc/config.gz' > board/orangepi/zero2w/linux.config`. (arm64 has no `sunxi_defconfig`, and a stock arm64 `defconfig` lacks `SQUASHFS=y` for the squashfs root — so the known-good captured config is the baseline, folding in the old Task 2.)

```
BR2_aarch64=y
BR2_cortex_a53=y
BR2_CCACHE=y
BR2_TOOLCHAIN_EXTERNAL=y
BR2_PACKAGE_OVERRIDE_FILE="${BR2_EXTERNAL_OPENIPC_SBC_GS_PATH}/board/common/local.mk"
BR2_TARGET_GENERIC_HOSTNAME="openipcgs"
BR2_TARGET_GENERIC_ISSUE="Welcome to OpenIPC GS"
BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y
BR2_TARGET_GENERIC_ROOT_PASSWD="12345"
BR2_TARGET_GENERIC_PASSWD_SHA512=y
# BR2_TARGET_GENERIC_REMOUNT_ROOTFS_RW is not set
BR2_ENABLE_LOCALE_WHITELIST="C en_US en_US.UTF-8"
BR2_GENERATE_LOCALE="C.UTF-8 en_US.UTF-8"
BR2_ROOTFS_OVERLAY="${BR2_EXTERNAL_OPENIPC_SBC_GS_PATH}/board/common/overlay ${BR2_EXTERNAL_OPENIPC_SBC_GS_PATH}/board/orangepi/zero2w/overlay ${BR2_EXTERNAL_OPENIPC_SBC_GS_PATH}/board/local/overlay"
BR2_ROOTFS_POST_BUILD_SCRIPT="${BR2_EXTERNAL_OPENIPC_SBC_GS_PATH}/board/common/post-build-script.sh"
BR2_ROOTFS_POST_IMAGE_SCRIPT="support/scripts/genimage.sh ${BR2_EXTERNAL_OPENIPC_SBC_GS_PATH}/board/common/gen-boot-scr.sh"
BR2_ROOTFS_POST_SCRIPT_ARGS="-c ${BR2_EXTERNAL}/board/orangepi/zero2w/genimage.cfg"
BR2_LINUX_KERNEL=y
BR2_LINUX_KERNEL_CUSTOM_TARBALL=y
BR2_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION="file:///home/gilankpam/h618-kernel-work/opi-kernel-snapshot/linux-6.18.35-opi-sunxi.tar.gz"
BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG=y
BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE="${BR2_EXTERNAL_OPENIPC_SBC_GS_PATH}/board/orangepi/zero2w/linux.config"
BR2_LINUX_KERNEL_DTS_SUPPORT=y
BR2_LINUX_KERNEL_INTREE_DTS_NAME="allwinner/sun50i-h618-orangepi-zero2w"
BR2_LINUX_KERNEL_DTB_KEEP_DIRNAME=y
BR2_LINUX_KERNEL_INSTALL_TARGET=y
BR2_PACKAGE_BUSYBOX_CONFIG="${BR2_EXTERNAL}/package/busybox/busybox.config"
BR2_PACKAGE_BUSYBOX_SHOW_OTHERS=y
BR2_PACKAGE_DOSFSTOOLS=y
BR2_PACKAGE_DOSFSTOOLS_MKFS_FAT=y
BR2_PACKAGE_E2FSPROGS_RESIZE2FS=y
BR2_PACKAGE_LINUX_FIRMWARE=y
BR2_PACKAGE_PARTED=y
BR2_PACKAGE_UBOOT_TOOLS=y
BR2_PACKAGE_LIBDRM=y
BR2_PACKAGE_LIBDRM_INSTALL_TESTS=y
BR2_PACKAGE_DROPBEAR=y
BR2_PACKAGE_IPROUTE2=y
BR2_PACKAGE_IW=y
BR2_PACKAGE_OPENSSH=y
BR2_PACKAGE_WPA_SUPPLICANT=y
BR2_PACKAGE_WPA_SUPPLICANT_AP_SUPPORT=y
BR2_PACKAGE_KMOD_TOOLS=y
BR2_PACKAGE_UTIL_LINUX_AGETTY=y
BR2_TARGET_ROOTFS_SQUASHFS=y
BR2_TARGET_ROOTFS_SQUASHFS4_ZSTD=y
# BR2_TARGET_ROOTFS_TAR is not set
BR2_TARGET_UBOOT=y
BR2_TARGET_UBOOT_BOARD_DEFCONFIG=y
BR2_TARGET_UBOOT_BOARD_DEFCONFIG="orangepi_zero2w"
BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES="${BR2_EXTERNAL_OPENIPC_SBC_GS_PATH}/board/orangepi/zero2w/uboot.fragment"
BR2_TARGET_UBOOT_FORMAT_CUSTOM=y
BR2_TARGET_UBOOT_FORMAT_CUSTOM_NAME="u-boot-sunxi-with-spl.bin"
BR2_TARGET_UBOOT_NEEDS_DTC=y
BR2_TARGET_UBOOT_NEEDS_PYLIBFDT=y
BR2_TARGET_UBOOT_NEEDS_ATF_BL31=y
BR2_TARGET_ARM_TRUSTED_FIRMWARE=y
BR2_TARGET_ARM_TRUSTED_FIRMWARE_LATEST_VERSION=y
BR2_TARGET_ARM_TRUSTED_FIRMWARE_PLATFORM="sun50i_h616"
BR2_TARGET_ARM_TRUSTED_FIRMWARE_BL31=y
BR2_PACKAGE_HOST_E2FSPROGS=y
BR2_PACKAGE_HOST_GENIMAGE=y
BR2_PACKAGE_HOST_UBOOT_TOOLS=y
BR2_PACKAGE_HOST_SWIG=y
```

- [ ] **Step 5: Write `board/orangepi/zero2w/uboot.fragment`** (squashfs read support in U-Boot, like radxa)

Create: `board/orangepi/zero2w/uboot.fragment`

```
CONFIG_CMD_SQUASHFS=y
CONFIG_FS_SQUASHFS=y
CONFIG_ZSTD=y
CONFIG_BOOTDELAY=1
```

- [ ] **Step 6: Guard the Rockchip flash include in `external.mk`**

Change:

```makefile
ifeq ($(BR2_PACKAGE_HOST_RKDEVELOPTOOL),y)
include $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/board/radxa/zero3/flash.mk
endif
```

This already exists and is correctly guarded by `BR2_PACKAGE_HOST_RKDEVELOPTOOL` — **verify** it reads exactly this (the OPi defconfig does not set `BR2_PACKAGE_HOST_RKDEVELOPTOOL`, so the include is skipped). If it is not guarded, wrap it as above. No other change.

- [ ] **Step 7: Make `build.sh` u-boot artifact handling board-aware**

In the `if [ $TARGET = "all" ]` block, replace:

```bash
        cd $OUTPUT_DIR/$DEFCONFIG/images
        cp u-boot-rockchip.bin u-boot.bin
```

with:

```bash
        cd $OUTPUT_DIR/$DEFCONFIG/images
        if [ -f u-boot-rockchip.bin ]; then
            cp u-boot-rockchip.bin u-boot.bin
        elif [ -f u-boot-sunxi-with-spl.bin ]; then
            cp u-boot-sunxi-with-spl.bin u-boot.bin
        fi
```

- [ ] **Step 8: Create the overlay placeholder**

```bash
mkdir -p board/orangepi/zero2w/overlay
touch board/orangepi/zero2w/overlay/.empty
```

- [ ] **Step 9: Smoke-check that Rockchip still configures (no regression)**

Run: `./build.sh radxa_zero3_defconfig 2>&1 | tail -5` is heavy; instead just re-run defconfig:
```bash
DEFCONFIG=radxa_zero3_defconfig ./build.sh savedefconfig 2>&1 | tail -5 || true
```
Expected: no error from the `external.mk` / `gen-boot-scr.sh` edits (they are additive/guarded).

- [ ] **Step 10: Build the OPi image**

Run:
```bash
DEFCONFIG=orangepi_zero2w_defconfig ./build.sh
```
Expected: build completes; `output/orangepi_zero2w_defconfig/images/` contains `u-boot-sunxi-with-spl.bin`, `rootfs.squashfs`, `sdcard.img`, `orangepi_zero2w_sdcard.img`, `orangepi_zero2w_boot.scr`.
Expected FAIL modes to fix here: ATF `sun50i_h616` BL31 wiring, missing `BR2_TARGET_UBOOT_NEEDS_ATF_BL31`, or genimage offset overlap — resolve before proceeding.

- [ ] **Step 11: Flash to a second microSD and boot on the board**

```bash
sudo dd if=output/orangepi_zero2w_defconfig/images/orangepi_zero2w_sdcard.img of=/dev/sdX bs=4M conv=fsync status=progress
```
Insert into the OPi Zero 2W, attach USB-UART to the debug pins, open serial at 115200.
Expected before: blank / no boot.
Expected after: SPL + U-Boot banner, `boot.scr` runs, kernel boots, **login prompt on serial**. If U-Boot cannot read the kernel from squashfs (path/partition wrong), adjust `boot.cmd` (Step 2) — common fixes: partition index, `${fdtfile}` path under `/boot/dtb/`, or fall back to U-Boot distro/extlinux. Re-build + re-flash until it reaches a login prompt.

- [ ] **Step 12: Confirm USB-OTG gadget networking for headless access**

Per `board/common`, hold Left during boot for gadget mode; host should see `192.168.5.1`.
```bash
ssh root@192.168.5.1   # password: 12345
```
Expected: shell. (If gadget mode needs board-specific UDC/dr_mode, note it for Task 6's overlay; serial console is sufficient to proceed.)

- [ ] **Step 13: Commit**

```bash
git add configs/orangepi_zero2w_defconfig board/orangepi/zero2w external.mk build.sh board/common/gen-boot-scr.sh
git commit -m "feat(orangepi-zero2w): sunxi platform scaffold + live-board kernel config"
```

---

### Task 2: (folded into Task 1)

**Merged during execution.** This task originally switched the kernel from a stock `sunxi_defconfig` to the live-board captured config. But arm64 has no `sunxi_defconfig`, and a stock arm64 `defconfig` lacks `SQUASHFS=y` for the squashfs root — so there is no useful stock-kernel intermediate. Task 1 now captures and uses `board/orangepi/zero2w/linux.config` directly (committed as `fix(orangepi-zero2w): use live-board kernel config baseline (fold Task 2)`).

The on-hardware "boots + core peripherals" check that lived here is performed at the **Task 1 first-boot milestone** (see Task 1 Steps 10–12): `uname -r` = `6.18.35`, `cma=256M` in `/proc/cmdline`, `ls /sys/class/drm` shows a card, and `dmesg | grep -iE 'cedrus|sun4i-drm|sun8i'` shows the drivers probing. No separate work remains.

---

### Task 3: REVERT — Cedrus/DE33 video is in the kernel snapshot

**Reverted by the Option-1 pivot.** The kernel is now the Armbian-patched source snapshot, which **already contains** the DE33 driver, the operator's `0099`/`0100` (verified applied in the snapshot: `sun8i_vi_layer_de33_formats[]` has `NV12`/`NV21`/…; the cedrus tiled `NV12_32L32` capture entry is removed), and the HDMI display DTS. Re-applying `0099`/`0100` would double-apply and fail. The captured `.config` already enables all the video symbols, so the fragment is redundant too.

**Files (undo the original Task 3 commit `36b8d02`):**
- Delete: `board/orangepi/zero2w/linux-patches/0099-de33-enable-nv12-vi-plane.patch`
- Delete: `board/orangepi/zero2w/linux-patches/0100-cedrus-prefer-linear-nv12.patch`
- Delete: `board/orangepi/zero2w/linux.fragment`
- Modify: `configs/orangepi_zero2w_defconfig` — remove the `BR2_LINUX_KERNEL_PATCH` and `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES` lines added by `36b8d02`.

- [ ] **Step 1: Remove the patches, fragment, and the two defconfig lines**

```bash
git rm board/orangepi/zero2w/linux-patches/0099-de33-enable-nv12-vi-plane.patch \
       board/orangepi/zero2w/linux-patches/0100-cedrus-prefer-linear-nv12.patch \
       board/orangepi/zero2w/linux.fragment
rmdir board/orangepi/zero2w/linux-patches 2>/dev/null || true
# remove the two lines from the defconfig:
sed -i '/BR2_LINUX_KERNEL_PATCH=/d;/BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES=/d' configs/orangepi_zero2w_defconfig
```

- [ ] **Step 2: Verify the defconfig no longer references patches/fragment**

```bash
grep -nE 'BR2_LINUX_KERNEL_PATCH|CONFIG_FRAGMENT_FILES' configs/orangepi_zero2w_defconfig || echo "clean (no patch/fragment refs)"
```
Expected: "clean".

- [ ] **Step 3: Commit**

```bash
git add -A board/orangepi/zero2w configs/orangepi_zero2w_defconfig
git commit -m "revert(orangepi-zero2w): drop 0099/0100/fragment — already in kernel snapshot"
```

(Video is validated at the Task 4/6 milestone via `modetest -p` showing the `NV12` overlay plane + `/dev/video0` Cedrus — the snapshot kernel provides it. HDMI now works because the snapshot DTS enables `&de`/`&hdmi`, which mainline lacked.)

---

### Task 4: Onboard WiFi — UWE5622 firmware (driver is in the snapshot)

The uwe5622 **driver and the SDIO WiFi DTS are already in the kernel snapshot**, and the captured `.config` enables `CONFIG_WLAN_UWE5622=m`/`CONFIG_SPRDWL_NG=m`/`CONFIG_UNISOC_WIFI_PS=y` — so the kernel build produces `sprdwl_ng.ko`/`sunxi_addr.ko` and installs them. This task only ships the **firmware** the driver loads, plus an autoload entry.

**Files:**
- Create: `board/orangepi/zero2w/overlay/lib/firmware/uwe5622/{wcnmodem.bin,wcnmodem-38222.bin,wifi_2355b001_1ant.ini}`
- Create: `board/orangepi/zero2w/overlay/lib/firmware/wcnmodem.bin` (symlink → `uwe5622/wcnmodem.bin`)
- Create: `board/orangepi/zero2w/overlay/etc/modules-load.d/uwe5622.conf`

**Interfaces:**
- Consumes: the kernel snapshot (driver + DTS) + captured `.config` (WiFi symbols).
- Produces: firmware under `/lib/firmware/uwe5622/`; `wlan0` once `sprdwl_ng` loads.

- [ ] **Step 1: Install the firmware from the reference board via the overlay**

```bash
mkdir -p board/orangepi/zero2w/overlay/lib/firmware/uwe5622
scp root@192.168.10.91:/lib/firmware/uwe5622/wcnmodem.bin \
    root@192.168.10.91:/lib/firmware/uwe5622/wcnmodem-38222.bin \
    root@192.168.10.91:/lib/firmware/uwe5622/wifi_2355b001_1ant.ini \
    board/orangepi/zero2w/overlay/lib/firmware/uwe5622/
ln -sf uwe5622/wcnmodem.bin board/orangepi/zero2w/overlay/lib/firmware/wcnmodem.bin
```
Also check the reference board for a `wifi_2355b001_1ant.ini` symlink at `/lib/firmware/` and replicate it if present.

- [ ] **Step 2: Autoload the driver at boot**

Create `board/orangepi/zero2w/overlay/etc/modules-load.d/uwe5622.conf`:
```
sprdwl_ng
```

- [ ] **Step 3: Verify the overlay contents**

```bash
find board/orangepi/zero2w/overlay/lib/firmware -type f -o -type l
test -s board/orangepi/zero2w/overlay/lib/firmware/uwe5622/wcnmodem.bin && echo "firmware present"
```
Expected: the three firmware files + the symlink + `modules-load.d/uwe5622.conf`.

- [ ] **Step 4: Commit**

```bash
git add board/orangepi/zero2w/overlay
git commit -m "feat(orangepi-zero2w): ship UWE5622 onboard-WiFi firmware + autoload"
```

- [ ] **Step 5: (At the WiFi milestone build) bring up wlan0 on hardware**

After the next full build + flash, on the board:
```bash
dmesg | grep -iE 'sprd|uwe5622|wcn|wlan'    # firmware load + wlan0 registered (sprdwl_ng autoloaded)
ip link show wlan0
iw dev wlan0 scan | grep SSID | head        # station scan works
modetest -p | grep -i NV12                  # video plane present (snapshot kernel) — same milestone
```
Expected: `wlan0` present, firmware loaded, scan returns SSIDs; NV12 overlay plane present.

---

### Task 5: ffmpeg with `--enable-v4l2-request`

Provide the decode backend the operator's player links against, built against the Cedrus/V4L2-request kernel path.

**Files:**
- Modify: `configs/orangepi_zero2w_defconfig` (enable ffmpeg + needed demux/decode)
- Modify: `external.mk` (append the configure opt)
- Create (only if needed): `board/orangepi/zero2w/patches/ffmpeg/*.patch` + set `BR2_GLOBAL_PATCH_DIR`

**Interfaces:**
- Consumes: the Cedrus kernel path (Task 3).
- Produces: `/usr/bin/ffmpeg` + libav* with `AV_HWDEVICE_TYPE_V4L2REQUEST` and DRM-PRIME output.

- [ ] **Step 1: Enable ffmpeg in the defconfig**

Add to `configs/orangepi_zero2w_defconfig`:
```
BR2_PACKAGE_FFMPEG=y
BR2_PACKAGE_FFMPEG_GPL=y
BR2_PACKAGE_FFMPEG_HWACCEL=y
BR2_PACKAGE_FFMPEG_SWSCALE=y
```

- [ ] **Step 2: Append the v4l2-request configure opt in `external.mk`**

Buildroot's ffmpeg `Config.in` has no v4l2-request toggle, so append it from the external tree. Add near the other package overrides in `external.mk`:

```makefile
# Orange Pi Zero 2W: ffmpeg needs the V4L2 Request API hwaccel (Cedrus).
ifeq ($(BR2_PACKAGE_FFMPEG),y)
FFMPEG_CONF_OPTS += --enable-v4l2-request --enable-libdrm
FFMPEG_DEPENDENCIES += libdrm
endif
```

- [ ] **Step 3: Build ffmpeg and check the feature is on**

```bash
DEFCONFIG=orangepi_zero2w_defconfig ./build.sh ffmpeg-rebuild 2>&1 | tee /tmp/ff.log | grep -iE 'v4l2.?request|libdrm|ERROR'
grep -i 'v4l2_request' output/orangepi_zero2w_defconfig/build/ffmpeg-*/config.h 2>/dev/null || \
  grep -i 'v4l2-request' /tmp/ff.log
```
Expected: configure reports v4l2-request enabled. If configure errors ("v4l2-request not found"), the v4l2-request hwaccel needs kernel-header/source support → add an ffmpeg patch under `board/orangepi/zero2w/patches/ffmpeg/` and set `BR2_GLOBAL_PATCH_DIR="${BR2_EXTERNAL_OPENIPC_SBC_GS_PATH}/board/orangepi/zero2w/patches"` in the defconfig; re-run. (Prototype the working flags first by inspecting how the reference board's ffmpeg was built.)

- [ ] **Step 4: Reflash and verify HW decode on the board**

Copy a short 8-bit HEVC sample to the board, then:
```bash
ffmpeg -hide_banner -init_hw_device v4l2request=v4l:/dev/media0 \
  -hwaccel v4l2request -i sample.mkv -f null - 2>&1 | tail -20
```
Expected: decode runs through the Cedrus V4L2-request path with the CPU near idle (the GPU/sw path is what we avoid). Exact device/args may need tuning; the success criterion is **HW-accelerated decode without falling back to software**.

- [ ] **Step 5: Commit**

```bash
git add configs/orangepi_zero2w_defconfig external.mk board/orangepi/zero2w/patches 2>/dev/null
git commit -m "feat(orangepi-zero2w): ffmpeg with --enable-v4l2-request (Cedrus decode backend)"
```

---

### Task 6: wfb link (stock wifibroadcast-ng, no fpvd), drop Rockchip-only packages, final MVP image

Enable the stock OpenIPC wfb link stack so a USB RTL adapter carries the link and `wifibroadcast-ng` forwards video to UDP:5600 for the operator's player. **No `fpvd` on this board in v1** — `fpvd.mk` is not touched. Drop Rockchip-only packages and produce the final MVP image.

**Files:**
- Modify: `configs/orangepi_zero2w_defconfig` (enable wfb stack + RTL drivers + hotspot deps; keep Rockchip-only and fpvd off)
- Create (only if the stock link config needs a board tweak): files under `board/orangepi/zero2w/overlay/etc/`

**Interfaces:**
- Consumes: WiFi (Task 4), ffmpeg (Task 5).
- Produces: the final `orangepi_zero2w_sdcard.img` MVP; video forwarded to `127.0.0.1:5600` by `S98wifibroadcast` for the operator's player.

- [ ] **Step 1: Confirm the stock wfb link + UDP:5600 forwarding path**

```bash
# wifibroadcast-ng ships the link init + binaries; confirm the forward target.
grep -rniE '5600|udp|wfb_rx|forward' package/wifibroadcast-ng/ 2>/dev/null | head
ls package/wifibroadcast-ng/
```
Note where `S98wifibroadcast` forwards video (expected `127.0.0.1:5600`). This is the pre-fpvd path the player will read; no fpvd needed.

- [ ] **Step 2: Enable the wfb link stack + RTL drivers in the defconfig (no fpvd)**

Add to `configs/orangepi_zero2w_defconfig`:

```
BR2_PACKAGE_PYTHON3=y
BR2_PACKAGE_PYTHON_PYYAML=y
BR2_PACKAGE_PYTHON_PYROUTE2=y
BR2_PACKAGE_WIRELESS_REGDB=y
BR2_PACKAGE_WIFIBROADCAST_NG=y
BR2_PACKAGE_WFB_SERVER=y
BR2_PACKAGE_RTL8812AU=y
BR2_PACKAGE_RTL88X2EU=y
BR2_PACKAGE_RTL88X2CU=y
BR2_PACKAGE_DNSMASQ=y
BR2_PACKAGE_DOSFSTOOLS_FATLABEL=y
BR2_PACKAGE_DOSFSTOOLS_FSCK_FAT=y
# Off in v1 — fpvd is a follow-up (operator's call):
# BR2_PACKAGE_FPVD
# Rockchip-only — keep OFF:
# BR2_PACKAGE_PIXELPILOT, BR2_PACKAGE_ROCKCHIP_MPP, BR2_PACKAGE_LIBRGA,
# BR2_PACKAGE_MALI_DRIVER_CUSTOM, BR2_PACKAGE_ROCKCHIP_RKBIN, BR2_PACKAGE_HOST_RKDEVELOPTOOL
```
Also set the GPIO pins for this board (verify the OPi Zero 2W 40-pin header against the desired buttons):
```
BR2_BOARD_GPIO_CONFIG_PIN_NAME=y
BR2_FACTORY_RESET_GPIO_PIN_NAME="PIN_<n>"
BR2_GADGET_MODE_GPIO_PIN_NAME="PIN_<m>"
```
(Pick free header pins; `<n>`/`<m>` are a board decision — confirm with `gpioinfo` on the booted board and the OPi Zero 2W pinout.)

- [ ] **Step 3: Build the full image**

Run: `DEFCONFIG=orangepi_zero2w_defconfig ./build.sh`
Expected: completes; fpvd / pixelpilot / rockchip-mpp / librga / mali are NOT built (confirm: `ls output/orangepi_zero2w_defconfig/build | grep -iE 'fpvd|pixelpilot|rockchip-mpp|librga|mali'` → empty).

- [ ] **Step 4: Reflash and validate the MVP end-to-end**

On the board:
```bash
uname -r                          # 6.18.35
ip link show wlan0                # onboard WiFi present
/etc/init.d/S98wifibroadcast status 2>/dev/null; pgrep -a wfb_rx   # link init + rx running
# attach a USB RTL adapter; confirm it binds an RTL wfb driver:
dmesg | grep -iE '88xxau|8812au|88x2eu|88x2cu'
# with a transmitting drone/test source, confirm video reaches UDP:5600:
timeout 3 socat -u UDP-RECV:5600 - | head -c 64 | xxd | head
modetest -p | grep -i NV12        # video substrate still present for the player
```
Expected: boots, onboard WiFi up, `S98wifibroadcast` running, USB RTL adapter binds, video bytes arrive on UDP:5600, NV12 plane ready. **No on-screen video yet** (operator's player not installed) — that is the defined v1 boundary. (`socat` is optional; if not in the image use `tcpdump`/`nc -lu 5600`.)

- [ ] **Step 5: Commit**

```bash
git add configs/orangepi_zero2w_defconfig board/orangepi/zero2w/overlay
git commit -m "feat(orangepi-zero2w): stock wfb link (no fpvd), drop Rockchip pkgs, MVP image"
```

---

### Task 7: Trim the kernel config for a radxa-sized image

The Task 2 baseline carries the full Armbian distro config (~2547 modules). Trim it to only what this board+GS needs, validating the trimmed kernel still boots with WiFi + video.

**Files:**
- Modify: `board/orangepi/zero2w/linux.config`

**Interfaces:**
- Consumes: the validated full-config image (Task 6).
- Produces: a smaller `linux.config` that still satisfies all prior tasks' on-board checks.

- [ ] **Step 1: Measure the starting point**

```bash
du -h output/orangepi_zero2w_defconfig/images/rootfs.squashfs
du -sh output/orangepi_zero2w_defconfig/target/lib/modules
grep -c '=m' board/orangepi/zero2w/linux.config
# Compare to a Rockchip board for the target size:
du -h output/radxa_zero3_defconfig/images/rootfs.squashfs 2>/dev/null
```

- [ ] **Step 2: Disable unneeded module classes**

Edit `board/orangepi/zero2w/linux.config`, turning `=m` → `# ... is not set` for subsystems this GS does not use (keep: sunxi/H616 clk/pinctrl/mmc/usb/dwmac, cedrus + sun4i/DE33 DRM, dmabuf, squashfs/overlay, cfg80211/mac80211, the RTL USB WiFi the wfb link uses, UWE5622 symbols, USB gadget, INA2xx if used). Candidate removals: other-vendor WiFi/Ethernet, sound cards beyond HDMI, btrfs/other FS, infiniband, media drivers other than cedrus, most HID/input, virtualization, other-arch crypto. Keep the `linux.fragment` symbols authoritative (they re-assert the must-haves regardless of trimming).

- [ ] **Step 3: Rebuild and re-validate the full chain**

```bash
DEFCONFIG=orangepi_zero2w_defconfig ./build.sh linux-rebuild 2>&1 | grep -iE 'error|cedrus|sprdwl' ; DEFCONFIG=orangepi_zero2w_defconfig ./build.sh
du -h output/orangepi_zero2w_defconfig/images/rootfs.squashfs   # smaller
```
Reflash and re-run the on-board checks from Tasks 2/3/4/6: boots, `modetest -p` shows NV12, `wlan0` comes up and scans, fpvd serves :8080. If any regress, the trim removed a needed symbol — restore it (the fragment is the safety net for the must-haves) and rebuild.

- [ ] **Step 4: Commit**

```bash
git add board/orangepi/zero2w/linux.config
git commit -m "perf(orangepi-zero2w): trim kernel config to radxa-sized image"
```

---

## Self-review

**Spec coverage:**
- New sunxi platform + defconfig → Task 1. ✓
- Native mainline 6.18 kernel + trimmed config → Tasks 1/2/7. ✓
- Video patches 0099/0100 + Cedrus/DE33 → Task 3. ✓
- UWE5622 W1 in-tree + firmware + DTS check → Task 4. ✓
- ffmpeg --enable-v4l2-request → Task 5. ✓
- sunxi u-boot + ATF, MBR/SPL@8K image, sunxi boot.cmd → Task 1. ✓
- Board-aware external.mk / build.sh / gen-boot-scr.sh → Task 1. ✓
- Stock `wifibroadcast-ng` wfb link (no fpvd in v1) + drop Rockchip pkgs → Task 6. ✓
- Player out of scope; video forwarded to UDP:5600 for the operator's player → Task 6. ✓
- fpvd out of scope in v1 (`BR2_PACKAGE_FPVD` off; `fpvd.mk` untouched) → Task 6 Step 2. ✓
- Bluetooth out of scope → not enabled (only `sprdwl_ng` in modules-load). ✓

**Open verification items (from the spec) are handled as explicit in-task steps, not placeholders:** DTS WiFi nodes (Task 4 Step 4, with the exact diff commands + branch), ffmpeg v4l2-request patch (Task 5 Step 3, with the fallback path), GPIO pins (Task 6 Step 2, with `gpioinfo` confirmation).

**Type/name consistency:** patch dir `board/orangepi/zero2w/linux-patches`, fragment `board/orangepi/zero2w/linux.fragment`, config `board/orangepi/zero2w/linux.config`, artifact `u-boot-sunxi-with-spl.bin`, image `orangepi_zero2w_sdcard.img` — used consistently across tasks.
