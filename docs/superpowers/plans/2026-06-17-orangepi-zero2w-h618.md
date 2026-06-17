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

- **Kernel:** mainline Linux **6.18.x** (match the validated `6.18.35`). Built in Buildroot from a custom tarball; no Armbian kernel tree.
- **Onboard WiFi = W1:** replay the Armbian UWE5622 patch subset **in-tree** as `BR2_LINUX_KERNEL_PATCH`; no out-of-tree kernel-module package. Firmware ships via the **board rootfs overlay**, not a package.
- **Video userspace = `ffmpeg --enable-v4l2-request` only.** No new player package; the player is the operator's separate work. Leave the fpvd player hook as a placeholder.
- **Image:** MBR partition table, `u-boot-sunxi-with-spl.bin` at **8K**, squashfs rootfs, **SD-boot only** (no eMMC flasher).
- **Additive only:** do not change any Rockchip board's defconfig or `board/radxa/zero3/`. After every task, `radxa_zero3` must still build (smoke-check in Task 1, then trust).
- **Target:** `BR2_aarch64=y`, `BR2_cortex_a53=y` (H618 is Cortex-A53).
- Branch: `feat/orangepi-zero2w`. Commit per task.

---

### Task 1: Sunxi platform scaffold — minimal bootable image

Stand up the new platform end-to-end with a **stock `sunxi_defconfig` kernel**, isolating "the board boots" (u-boot + ATF + image layout + boot script + build wiring) from "our kernel recipe" (Task 2+).

**Files:**
- Create: `configs/orangepi_zero2w_defconfig`
- Create: `board/orangepi/zero2w/genimage.cfg`
- Create: `board/orangepi/zero2w/boot.cmd`
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

Start from `radxa_zero3_defconfig` and apply the platform changes. The kernel uses stock `sunxi_defconfig` for this task only.

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
BR2_LINUX_KERNEL_CUSTOM_VERSION=y
BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="6.18.35"
BR2_LINUX_KERNEL_USE_DEFCONFIG=y
BR2_LINUX_KERNEL_DEFCONFIG="sunxi"
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
BR2_TARGET_ARM_TRUSTED_FIRMWARE_CUSTOM_VERSION=y
BR2_TARGET_ARM_TRUSTED_FIRMWARE_CUSTOM_VERSION_VALUE="2.11"
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
git commit -m "feat(orangepi-zero2w): sunxi platform scaffold, boots stock sunxi_defconfig"
```

---

### Task 2: Switch to the live-board kernel config (known-good baseline)

Replace stock `sunxi_defconfig` with the operator's validated config captured from the running board, so subsequent video/WiFi work sits on a config proven to drive this exact hardware. (Size trimming is deferred to Task 7 — correctness first.)

**Files:**
- Create: `board/orangepi/zero2w/linux.config`
- Modify: `configs/orangepi_zero2w_defconfig` (point kernel at the custom config)

**Interfaces:**
- Consumes: the bootable platform from Task 1.
- Produces: `BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG` → `board/orangepi/zero2w/linux.config`. Tasks 3–4 add a `linux.fragment` layered on top; Task 7 trims this file.

- [ ] **Step 1: Capture the running config from the reference board**

```bash
ssh root@192.168.10.91 'zcat /proc/config.gz' > board/orangepi/zero2w/linux.config
wc -l board/orangepi/zero2w/linux.config   # ~9600 lines
```

- [ ] **Step 2: Point the defconfig at the custom config**

In `configs/orangepi_zero2w_defconfig`, replace:

```
BR2_LINUX_KERNEL_USE_DEFCONFIG=y
BR2_LINUX_KERNEL_DEFCONFIG="sunxi"
```

with:

```
BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG=y
BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE="${BR2_EXTERNAL_OPENIPC_SBC_GS_PATH}/board/orangepi/zero2w/linux.config"
```

- [ ] **Step 3: Build**

Run: `DEFCONFIG=orangepi_zero2w_defconfig ./build.sh linux-rebuild 2>&1 | tail -20` then `DEFCONFIG=orangepi_zero2w_defconfig ./build.sh`
Expected: kernel builds against 6.18.35. Buildroot runs `olddefconfig`; if any Armbian-only symbols are dropped that is expected (they belong to out-of-tree drivers added later). Build completes; image produced.
Expected FAIL to fix: build errors from config symbols referencing not-yet-present out-of-tree drivers — none should remain after `olddefconfig` since those symbols simply won't exist; if a symbol forces a missing in-tree driver, leave it (`olddefconfig` clears unmet deps).

- [ ] **Step 4: Reflash and verify boot + core peripherals**

Flash (Task 1 Step 11), boot, and on the board check:
```bash
uname -r                 # 6.18.35
cat /proc/cmdline        # cma=256M present
ls /sys/class/drm        # card0 + HDMI connector
dmesg | grep -iE 'cedrus|sun4i-drm|sun8i'   # drivers probed
```
Expected before (Task 1 stock config): may differ.
Expected after: boots, `uname -r` = `6.18.35`, DRM card present, sun4i/cedrus drivers probe.

- [ ] **Step 5: Commit**

```bash
git add board/orangepi/zero2w/linux.config configs/orangepi_zero2w_defconfig
git commit -m "feat(orangepi-zero2w): use validated live-board kernel config baseline"
```

---

### Task 3: Hardware video path — Cedrus + DE33 NV12 overlay plane

Apply the operator's two patches and confirm the kernel exposes the NV12 overlay plane and the Cedrus decoder — the substrate the operator's player needs.

**Files:**
- Create: `board/orangepi/zero2w/linux-patches/0099-de33-enable-nv12-vi-plane.patch` (copy)
- Create: `board/orangepi/zero2w/linux-patches/0100-cedrus-prefer-linear-nv12.patch` (copy)
- Create: `board/orangepi/zero2w/linux.fragment` (assert the video symbols)
- Modify: `configs/orangepi_zero2w_defconfig` (add `BR2_LINUX_KERNEL_PATCH` + fragment)

**Interfaces:**
- Consumes: the known-good config baseline (Task 2).
- Produces: `BR2_LINUX_KERNEL_PATCH="${...}/board/orangepi/zero2w/linux-patches"`; `linux.fragment` (Task 4 appends WiFi symbols to this same file). Confirmed kernel capability: DRM plane with `NV12` + `/dev/video0` = Cedrus.

- [ ] **Step 1: Copy the video patches into the board tree**

```bash
mkdir -p board/orangepi/zero2w/linux-patches
cp ~/Projects/h618-mainline-video/patches/0099-de33-enable-nv12-vi-plane.patch \
   ~/Projects/h618-mainline-video/patches/0100-cedrus-prefer-linear-nv12.patch \
   board/orangepi/zero2w/linux-patches/
```

- [ ] **Step 2: Create `board/orangepi/zero2w/linux.fragment`** (assert the video symbols are built-in)

```
# --- Filesystem (squashfs root + overlay) ---
CONFIG_SQUASHFS=y
CONFIG_OVERLAY_FS=y
CONFIG_MODULE_COMPRESS_NONE=y

# --- Cedrus HW video decode + sun4i/DE33 DRM (patches 0099/0100 act on these) ---
CONFIG_MEDIA_SUPPORT=y
CONFIG_MEDIA_CONTROLLER=y
CONFIG_V4L_MEM2MEM_DRIVERS=y
CONFIG_VIDEO_SUNXI_CEDRUS=y
CONFIG_DRM=y
CONFIG_DRM_SUN4I=y
CONFIG_DRM_SUN8I_MIXER=y
CONFIG_DRM_SUN8I_DW_HDMI=y
CONFIG_DMABUF_HEAPS=y
CONFIG_DMABUF_HEAPS_CMA=y
CONFIG_DMABUF_HEAPS_SYSTEM=y
```

- [ ] **Step 3: Wire patches + fragment into the defconfig**

Add to `configs/orangepi_zero2w_defconfig` (after the `BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE` line):

```
BR2_LINUX_KERNEL_PATCH="${BR2_EXTERNAL_OPENIPC_SBC_GS_PATH}/board/orangepi/zero2w/linux-patches"
BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="${BR2_EXTERNAL_OPENIPC_SBC_GS_PATH}/board/orangepi/zero2w/linux.fragment"
```

- [ ] **Step 4: Rebuild the kernel and confirm patches applied**

```bash
DEFCONFIG=orangepi_zero2w_defconfig ./build.sh linux-rebuild 2>&1 | tee /tmp/k.log | grep -iE 'Applying|0099|0100|patch'
```
Expected: both `0099` and `0100` apply cleanly. If a hunk fails against 6.18.35 (vs. the operator's tree), reconcile the patch context and re-run. Build the full image after.

- [ ] **Step 5: Reflash and validate the video plane + decoder on hardware**

On the booted board (HDMI attached):
```bash
modetest -p 2>/dev/null | grep -iE 'NV12|plane'   # expect an overlay plane listing NV12
ls -l /dev/video0
cat /sys/class/video4linux/video0/name            # expect a cedrus/codec name
```
Expected before (Task 2 baseline, no `0099`): no NV12 format on the VI plane.
Expected after: `modetest -p` lists `NV12` on the overlay plane; `/dev/video0` is the Cedrus decoder. (Full decode-to-screen is validated with ffmpeg in Task 5 / the operator's player.)

- [ ] **Step 6: Commit**

```bash
git add board/orangepi/zero2w/linux-patches board/orangepi/zero2w/linux.fragment configs/orangepi_zero2w_defconfig
git commit -m "feat(orangepi-zero2w): enable Cedrus + DE33 NV12 overlay (patches 0099/0100)"
```

---

### Task 4: Onboard WiFi — UWE5622 (W1, in-tree patch replay) + firmware

Bring up `wlan0` by replaying the Armbian UWE5622 patch subset as in-tree kernel patches, enabling the config symbols, shipping the firmware via the overlay, and confirming/adding the DTS SDIO nodes.

**Files:**
- Create: `board/orangepi/zero2w/linux-patches/uwe5622-*.patch` (subset, see Step 1)
- Create (maybe): `board/orangepi/zero2w/linux-patches/0200-orangepi-zero2w-wifi-nodes.patch` (DTS, only if mainline lacks the nodes)
- Modify: `board/orangepi/zero2w/linux.fragment` (append WiFi symbols)
- Create: `board/orangepi/zero2w/overlay/lib/firmware/uwe5622/*` + symlink
- Create: `board/orangepi/zero2w/overlay/etc/modules-load.d/uwe5622.conf`

**Interfaces:**
- Consumes: the kernel patch dir + fragment from Task 3.
- Produces: loadable modules `sprdwl_ng`, `sunxi_addr`; `wlan0` netdev; firmware under `/lib/firmware/uwe5622/`.

- [ ] **Step 1: Copy the version≥6.18 + sunxi patch subset, in apply order**

The base patch creates the whole `drivers/net/wireless/uwe5622/` subtree; the rest adapt it. Copy this exact subset from `~/h618-kernel-work/armbian-build/patch/misc/wireless-uwe5622/` and prefix with sequence numbers so `BR2_LINUX_KERNEL_PATCH` applies them in order (Buildroot applies `*.patch` alphabetically):

```bash
SRC=~/h618-kernel-work/armbian-build/patch/misc/wireless-uwe5622
DST=board/orangepi/zero2w/linux-patches
cp $SRC/uwe5622-allwinner-v6.3.patch                                  $DST/0300-uwe5622-allwinner-v6.3.patch
cp $SRC/uwe5622-allwinner-bugfix-v6.3.patch                           $DST/0301-uwe5622-allwinner-bugfix-v6.3.patch
cp $SRC/uwe5622-allwinner-v6.3-compilation-fix.patch                  $DST/0302-uwe5622-allwinner-v6.3-compilation-fix.patch
cp $SRC/uwe5622-v6.4-post.patch                                       $DST/0303-uwe5622-v6.4-post.patch
cp $SRC/uwe5622-warnings.patch                                        $DST/0304-uwe5622-warnings.patch
cp $SRC/uwe5622-v6.1.patch                                            $DST/0305-uwe5622-v6.1.patch
cp $SRC/uwe5622-park-link-v6.1-post.patch                             $DST/0306-uwe5622-park-link-v6.1-post.patch
cp $SRC/uwe5622-v6.6-fix-tty-sdio.patch                               $DST/0307-uwe5622-v6.6-fix-tty-sdio.patch
cp $SRC/uwe5622-fix-setting-mac-address-for-netdev.patch              $DST/0308-uwe5622-fix-mac-netdev.patch
cp $SRC/wireless-uwe5622-Fix-compilation-with-6.7-kernel.patch        $DST/0309-uwe5622-fix-6.7.patch
cp $SRC/wireless-uwe5622-reduce-system-load.patch                     $DST/0310-uwe5622-reduce-load.patch
cp $SRC/uwe5622-v6.9.patch                                            $DST/0311-uwe5622-v6.9.patch
cp $SRC/uwe5622-v6.11.patch                                           $DST/0312-uwe5622-v6.11.patch
cp $SRC/uwe5622-fix-spanning-writes.patch                             $DST/0313-uwe5622-fix-spanning-writes.patch
cp $SRC/uwe5622-fix-timer-api-changes-for-6.15-only-sunxi.patch       $DST/0314-uwe5622-timer-6.15-sunxi.patch
cp $SRC/uwe5622-v6.16.patch                                           $DST/0315-uwe5622-v6.16.patch
cp $SRC/uwe5622-v6.17.patch                                           $DST/0316-uwe5622-v6.17.patch
cp $SRC/uwe5622-v6.18.patch                                           $DST/0317-uwe5622-v6.18.patch
cp $SRC/wireless-uwe5622-Fix-missing-prototypes.patch                 $DST/0318-uwe5622-fix-missing-prototypes.patch
```

(This mirrors `driver_uwe5622()` for `version ≥ 6.18 && LINUXFAMILY == sun*`. The `-v6.19`/`-v7.1` patches are NOT applied — kernel is 6.18.)

- [ ] **Step 2: Add the Makefile-hook patch (wire the subtree into the kernel build)**

`driver_uwe5622()` appends `obj-$(CONFIG_SPARD_WLAN_SUPPORT) += uwe5622/` to `drivers/net/wireless/Makefile`. Encode that as a patch so the in-tree build picks up the subtree:

Create `board/orangepi/zero2w/linux-patches/0299-uwe5622-wireless-makefile.patch`:

```diff
--- a/drivers/net/wireless/Makefile
+++ b/drivers/net/wireless/Makefile
@@ -1,3 +1,5 @@
 # SPDX-License-Identifier: GPL-2.0
 #
 # Makefile for the Linux Wireless network device drivers.
+
+obj-$(CONFIG_SPARD_WLAN_SUPPORT) += uwe5622/
```

Verify the context lines against the real `drivers/net/wireless/Makefile` in the extracted 6.18.35 source (`output/orangepi_zero2w_defconfig/build/linux-6.18.35/drivers/net/wireless/Makefile`) and adjust the hunk header/context to match exactly. Numbered `0299` so it applies before the `03xx` base patch's referenced Kconfig is needed but after the source tree exists — if the base patch (`0300`) already edits this Makefile itself, **skip this step** (check `0300` first: `grep -l 'net/wireless/Makefile' $DST/0300-*.patch`).

- [ ] **Step 3: Append WiFi symbols to `board/orangepi/zero2w/linux.fragment`**

```
# --- Onboard UWE5622 WiFi (out-of-tree driver, added in-tree via patches) ---
CONFIG_STAGING=y
CONFIG_CFG80211=m
CONFIG_RFKILL=m
CONFIG_SPARD_WLAN_SUPPORT=y
CONFIG_WLAN_UWE5622=m
CONFIG_SPRDWL_NG=m
CONFIG_UNISOC_WIFI_PS=y
```

- [ ] **Step 4: Verify the DTS has the SDIO WiFi nodes; patch if missing**

Compare the reference board's live DT against mainline's built DTB:
```bash
# Reference (Armbian) — known to have the nodes:
ssh root@192.168.10.91 'ls -d /proc/device-tree/soc/mmc@4021000 /proc/device-tree/wifi-pwrseq /proc/device-tree/vcc-wifi-io'
# Mainline build output:
dtc -I dtb -O dts output/orangepi_zero2w_defconfig/build/linux-6.18.35/arch/arm64/boot/dts/allwinner/sun50i-h618-orangepi-zero2w.dtb 2>/dev/null | grep -iE 'mmc@4021000|wifi-pwrseq|vcc-wifi|sdio' 
```
Expected: if mainline already declares `mmc@4021000` (SDIO, `cap-sdio-irq`, `non-removable`, `mmc-pwrseq`) + a `wifi-pwrseq` + `vcc-wifi-io` regulator, **no DTS patch needed** — record that and skip to Step 5.
If missing: create `board/orangepi/zero2w/linux-patches/0200-orangepi-zero2w-wifi-nodes.patch` adding those nodes, derived from the delta between the Armbian DTS source (`~/h618-kernel-work/armbian-build/.../sun50i-h618-orangepi-zero2w.dts`) and mainline. Apply pin/reg/clock (32k) properties exactly as in the reference DT.

- [ ] **Step 5: Install the firmware via the board overlay**

```bash
mkdir -p board/orangepi/zero2w/overlay/lib/firmware/uwe5622
scp root@192.168.10.91:/lib/firmware/uwe5622/wcnmodem.bin \
    root@192.168.10.91:/lib/firmware/uwe5622/wcnmodem-38222.bin \
    root@192.168.10.91:/lib/firmware/uwe5622/wifi_2355b001_1ant.ini \
    board/orangepi/zero2w/overlay/lib/firmware/uwe5622/
ln -sf uwe5622/wcnmodem.bin board/orangepi/zero2w/overlay/lib/firmware/wcnmodem.bin
```
Create `board/orangepi/zero2w/overlay/etc/modules-load.d/uwe5622.conf`:
```
sprdwl_ng
```

- [ ] **Step 6: Build**

Run: `DEFCONFIG=orangepi_zero2w_defconfig ./build.sh linux-rebuild 2>&1 | grep -iE 'uwe5622|sprdwl|error'` then full `./build.sh`.
Expected: the `03xx` patches apply; `sprdwl_ng.ko` + `sunxi_addr.ko` build. Fix any 6.18 compile breakage by confirming the `0317-uwe5622-v6.18.patch` applied (it targets exactly this version).

- [ ] **Step 7: Reflash and bring up wlan0**

On the board:
```bash
modprobe sprdwl_ng
dmesg | grep -iE 'sprd|uwe5622|wcn|wlan'    # firmware load + wlan0 registered
ip link show wlan0
iw dev wlan0 scan | grep SSID | head        # station scan works
```
Expected before: no `wlan0`.
Expected after: `wlan0` present, firmware loaded, scan returns nearby SSIDs.

- [ ] **Step 8: Commit**

```bash
git add board/orangepi/zero2w/linux-patches board/orangepi/zero2w/linux.fragment board/orangepi/zero2w/overlay
git commit -m "feat(orangepi-zero2w): onboard UWE5622 WiFi via in-tree patch replay + firmware"
```

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

### Task 6: fpvd integration, drop Rockchip-only packages, final MVP image

Wire the GS stack: make fpvd's player dependency board-conditional (no pixelpilot on sunxi), ship a board `config.json` whose player hook points at the operator's future player, enable the wfb/RTL/hotspot packages, and produce the final MVP image.

**Files:**
- Modify: `package/fpvd/fpvd.mk` (board-conditional player dependency)
- Create: `board/orangepi/zero2w/overlay/etc/fpvd/config.json` (or the path fpvd reads) — player hook placeholder
- Modify: `configs/orangepi_zero2w_defconfig` (enable wfb stack, RTL drivers, fpvd, hotspot deps; keep Rockchip-only off)

**Interfaces:**
- Consumes: WiFi (Task 4), ffmpeg (Task 5).
- Produces: the final `orangepi_zero2w_sdcard.img` MVP.

- [ ] **Step 1: Inspect how fpvd selects/depends on the player**

```bash
sed -n '1,60p' package/fpvd/fpvd.mk
grep -n 'pixelpilot' package/fpvd/fpvd.mk package/fpvd/files/config.json
```
Note the exact `FPVD_DEPENDENCIES` line listing `pixelpilot` and the `config.json` `"pixelpilot"`/`"bin"` block. (Earlier survey: dep is hard-listed; `config.json` points `bin` at `/usr/bin/pixelpilot`, `rtpPort:5600`, `codec:h265`.)

- [ ] **Step 2: Make the pixelpilot dependency board-conditional in `package/fpvd/fpvd.mk`**

Change the dependency line so pixelpilot is only pulled when its package is enabled:

```makefile
FPVD_DEPENDENCIES = wifibroadcast-ng wfb-server python3 $(if $(BR2_PACKAGE_PIXELPILOT),pixelpilot)
```

(Match the surrounding style/exact existing dep list from Step 1; the key change is wrapping `pixelpilot` in `$(if $(BR2_PACKAGE_PIXELPILOT),...)`. Also guard the pixelpilot-launcher-retirement `rm -f` hook with the same condition so it is a no-op on sunxi.)

- [ ] **Step 3: Ship a board `config.json` with the player hook as a placeholder**

Copy the stock fpvd config and repoint the player at the operator's future binary. Determine the install path fpvd reads (from Step 1 — e.g. `/etc/fpvd/config.json`), then create `board/orangepi/zero2w/overlay/<that path>` with the `pixelpilot` block replaced by:

```json
  "player": {
    "enabled": false,
    "bin": "/usr/bin/h618-player",
    "env": {},
    "screenMode": "1920x1080@60",
    "codec": "h265",
    "rtpPort": 5600,
    "rtpJitterMs": 0
  }
```

Set `"enabled": false` so fpvd runs the wfb data plane + HTTP API without a player until the operator drops in `/usr/bin/h618-player`. Keep all other fpvd keys identical to the stock config. (If fpvd's schema requires the `pixelpilot` key name, keep the key name and only change `bin`/`enabled` — confirm against fpvd's config loader from Step 1.)

- [ ] **Step 4: Enable the GS stack in the defconfig**

Add to `configs/orangepi_zero2w_defconfig` (mirroring radxa's link stack, minus Rockchip-only):

```
BR2_PACKAGE_PYTHON3=y
BR2_PACKAGE_PYTHON_PYYAML=y
BR2_PACKAGE_PYTHON_TWISTED=y
BR2_PACKAGE_PYTHON_MSGPACK=y
BR2_PACKAGE_PYTHON_PYROUTE2=y
BR2_PACKAGE_WIRELESS_REGDB=y
BR2_PACKAGE_WIFIBROADCAST_NG=y
BR2_PACKAGE_WFB_SERVER=y
BR2_PACKAGE_FPVD=y
BR2_PACKAGE_RTL8812AU=y
BR2_PACKAGE_RTL88X2EU=y
BR2_PACKAGE_RTL88X2CU=y
BR2_PACKAGE_DNSMASQ=y
BR2_PACKAGE_DOSFSTOOLS_FATLABEL=y
BR2_PACKAGE_DOSFSTOOLS_FSCK_FAT=y
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

- [ ] **Step 5: Build the full image**

Run: `DEFCONFIG=orangepi_zero2w_defconfig ./build.sh`
Expected: completes; pixelpilot / rockchip-mpp / librga / mali are NOT built (confirm: `ls output/orangepi_zero2w_defconfig/build | grep -iE 'pixelpilot|rockchip-mpp|librga|mali'` → empty).

- [ ] **Step 6: Reflash and validate the MVP end-to-end**

On the board:
```bash
uname -r                          # 6.18.35
ip link show wlan0                # onboard WiFi present
systemctl status fpvd 2>/dev/null || /etc/init.d/S99fpvd status 2>/dev/null
# bring up a USB RTL adapter + wfb link as on radxa; confirm fpvd ingests it:
curl -s http://127.0.0.1:8080/ | head        # fpvd HTTP API responds
modetest -p | grep -i NV12        # video substrate still present for the player
```
Expected: boots, onboard WiFi up, fpvd supervises the wfb data plane and serves :8080, NV12 plane ready. **No player display yet** (operator's `h618-player` not installed) — that is the defined v1 boundary.

- [ ] **Step 7: Commit**

```bash
git add package/fpvd/fpvd.mk board/orangepi/zero2w/overlay configs/orangepi_zero2w_defconfig
git commit -m "feat(orangepi-zero2w): fpvd GS stack, drop Rockchip pkgs, MVP image"
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
- fpvd board-conditional + drop Rockchip pkgs + player hook → Task 6. ✓
- Player out of scope (hook placeholder) → Task 6 Step 3. ✓
- Bluetooth out of scope → not enabled (only `sprdwl_ng` in modules-load). ✓

**Open verification items (from the spec) are handled as explicit in-task steps, not placeholders:** DTS WiFi nodes (Task 4 Step 4, with the exact diff commands + branch), ffmpeg v4l2-request patch (Task 5 Step 3, with the fallback path), GPIO pins (Task 6 Step 4, with `gpioinfo` confirmation).

**Type/name consistency:** patch dir `board/orangepi/zero2w/linux-patches`, fragment `board/orangepi/zero2w/linux.fragment`, config `board/orangepi/zero2w/linux.config`, artifact `u-boot-sunxi-with-spl.bin`, image `orangepi_zero2w_sdcard.img`, player binary `/usr/bin/h618-player` — used consistently across tasks.
