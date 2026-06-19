# Orange Pi Zero 2W — In-House Kernel Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Orange Pi Zero 2W kernel entirely inside Buildroot — pristine mainline 6.18.35 from kernel.org + a curated in-repo patch subset + a trimmed config — eliminating the external Armbian-tree dependency and the 350 MB `.opi-artifacts` tarball.

**Architecture:** Swap `BR2_LINUX_KERNEL_CUSTOM_TARBALL` for `BR2_LINUX_KERNEL_CUSTOM_VERSION=y`/`..._VALUE="6.18.35"` + `BR2_GLOBAL_PATCH_DIR`. A manifest-driven extraction script copies a curated subset of Armbian's `sunxi-6.18` series (DE33 display, Cedrus, DTS tweak, UWE5622, the NV12 userpatches) into the repo as numbered patches. The dependency closure of that subset is grown empirically until the kernel builds, then proven on hardware; the config is then trimmed to what the board actually loads.

**Tech Stack:** Buildroot 2025.08.1, Linux 6.18.35 (aarch64, sunxi64/H618), GNU `patch`/`git`, Bash. Verification on hardware over SSH (`modetest`, `iw`, `dmesg`).

## Global Constraints

- **Kernel version:** exactly `6.18.35` (mainline stable from kernel.org). Do not bump.
- **DTS:** in-tree `allwinner/sun50i-h618-orangepi-zero2w` (already in mainline; do **not** add a board DTS patch — only SoC-level DE33/HDMI pipeline patches).
- **No initramfs.** Rootfs is squashfs on `mmcblk0p1`, mounted directly by the kernel. Therefore: **MMC (`MMC_SUNXI`) and squashfs (+zstd) must be built-in (`=y`)**; out-of-tree drivers (`uwe5622`, `rtl88x2*`) are modules (`=m`); display + Cedrus `=y`.
- **UWE5622 stays an in-tree kernel patch/module** (`CONFIG_AW_WIFI_DEVICE_UWE5622=y`, `CONFIG_WLAN_UWE5622=m`). Not a Buildroot package.
- **Scope:** Orange Pi Zero 2W only. Do not touch other defconfigs, U-Boot, ATF, ffmpeg, or the wfb stack.
- **Branch:** work on `feat/orangepi-zero2w` (already checked out). Commit after each task.
- **Commit convention:** `<type>(orangepi-zero2w): <subject>`, and every commit ends with the trailer
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` (passed as a second `-m`).

### Build & iteration command reference (used by every task)

Define once; reuse verbatim. `$REPO` is the repo root.

```bash
# Shorthand for direct Buildroot make calls against this board's output dir:
BR="make -C buildroot O=$REPO/output/orangepi_zero2w_defconfig BR2_EXTERNAL=$REPO"

# Full image build (downloads Buildroot on first run, applies defconfig, builds all):
DEFCONFIG=orangepi_zero2w_defconfig ./build.sh
#   -> output/orangepi_zero2w_defconfig/images/orangepi_zero2w_sdcard.img

# Apply defconfig once so the output .config exists (needed before $BR targets):
$BR orangepi_zero2w_defconfig

# Re-extract + re-patch + build the kernel (REQUIRED after changing patches/ or the patch dir):
$BR linux-dirclean linux

# Re-apply the custom .config + rebuild kernel (after editing board/.../linux.config):
$BR linux-reconfigure

# Copy the kernel build's .config back into the repo's custom config file:
$BR linux-update-config        # writes board/orangepi/zero2w/linux.config

# Rebuild the full image after a kernel change:
$BR all
```

> **Nix environment note:** this project builds under `nix-shell`. The `nix-shell --run '<cmd>'`
> form is broken in this FHS shell — instead pipe commands via stdin:
> `nix-shell <<'EOF'` … commands … `EOF`. (Outside Nix, run the commands directly.)

### THE BOOT-VERIFICATION GATE (V1–V5) — referenced by Tasks 3 and 4

Set `BOARD` to the board's SSH target (root, password `12345` per defconfig), e.g. `BOARD=root@192.168.x.x`.
Flash `output/orangepi_zero2w_defconfig/images/orangepi_zero2w_sdcard.img` to SD, boot, then:

```bash
# V1 — boots, correct kernel + root:
ssh $BOARD 'uname -r; cat /proc/cmdline'
#   expect: 6.18.35 ; root=/dev/mmcblk0p1 rootfstype=squashfs ... cma=256M

# V2 — WiFi/BT: driver bound, wlan0 present, hotspot DHCP up:
ssh $BOARD 'lsmod | grep -E "sprdwl_ng|sprdbt_tty"; ip link show wlan0; iw dev; pgrep -a dnsmasq'
#   expect: sprdwl_ng loaded; wlan0 exists; dnsmasq running

# V3 — display/DE33: DRM card + connector + plane:
ssh $BOARD 'ls /sys/class/drm/; modetest -M sun4i-drm 2>/dev/null | grep -A2 -iE "Connectors|Planes" | head; dmesg | grep -iE "sun4i|de33|hdmi" | tail'
#   expect: card0 + HDMI connector + at least one plane; no DE33 probe errors

# V4 — Cedrus video decode device present:
ssh $BOARD 'dmesg | grep -i cedrus; for d in /dev/video*; do echo $d; done; v4l2-ctl --list-devices 2>/dev/null'
#   expect: cedrus registered; a /dev/videoN stateless decoder node
#   (end-to-end: stream known H.265 to udp:5600 and confirm citruspilot renders on HDMI)

# V5 — storage intact:
ssh $BOARD 'lsblk; mount | grep -E "overlay|DVR|mmcblk"'
#   expect: rootfs (p1) + overlay/DVR partitions present
#   (gadget mode: hold Left on boot -> 192.168.5.1 reachable — manual check)
```

A task that says "run the V1–V5 gate" means: all five pass. Record any failure verbatim.

---

### Task 1: Patch-extraction tooling + seed manifest

Produce the manifest-driven extractor and the *seed* curated subset. The seed is deliberately incomplete (closure is grown in Task 2); this task's deliverable is a deterministic tool + a patch dir that regenerates exactly from the manifest.

**Files:**
- Create: `scripts/extract-kernel-patches.sh`
- Create: `board/orangepi/zero2w/kernel-patches.list` (the manifest)
- Create (generated, committed): `board/orangepi/zero2w/patches/linux/*.patch`
- Create: `board/orangepi/zero2w/patches/linux/README.md` (provenance note)

**Interfaces:**
- Produces: `scripts/extract-kernel-patches.sh` reads `kernel-patches.list` + an Armbian tree (`$ARMBIAN_BUILD`, default `~/h618-kernel-work/armbian-build`) and writes numbered patches into `board/orangepi/zero2w/patches/linux/`. Manifest line format (one per line, `#` comments, blank lines ignored), order preserved:
  - `series: <path-relative-to-patch/kernel/archive/sunxi-6.18>` — a stock series patch
  - `misc: <file-in-patch/misc/wireless-uwe5622>` — a uwe5622 driver patch
  - `user: <file-in-userpatches/kernel/archive/sunxi-6.18>` — a userpatch
  - `gen: uwe5622-wireless-makefile` — synthesize the `drivers/net/wireless/Makefile` append by diffing the Armbian worktree's Makefile against the pristine `v6.18.35` tag

- [ ] **Step 1: Write the seed manifest**

Create `board/orangepi/zero2w/kernel-patches.list`:

```
# Curated kernel patch subset for Orange Pi Zero 2W (H618), mainline 6.18.35.
# Order is application order (preserved as numbered files by extract-kernel-patches.sh).
# Sources, relative to the Armbian build tree ($ARMBIAN_BUILD):
#   series: patch/kernel/archive/sunxi-6.18/<path>
#   misc:   patch/misc/wireless-uwe5622/<file>
#   user:   userpatches/kernel/archive/sunxi-6.18/<file>
#   gen:    synthesized patch
#
# --- DE33 display core (sun4i -> DE33 refactor + H616 HDMI PHY + display-pipeline DT) ---
series: patches.drm/0001-drm-sun4i-mixer-Fix-up-DE33-channel-macros.patch
# ... (ALL of patches.drm/0001..0043, in series.conf order — fill from the dir listing)
#
# --- Cedrus / media ---
# ... (ALL of patches.media/*, in series.conf order)
#
# --- Orange Pi Zero 2W DTS tweak ---
series: patches.armbian/0302-arm64-dts-sun50i-h618-orangepi-zero2w-add-emac-sound.patch
#
# --- UWE5622 WiFi/BT driver (version-gated set for 6.18.x) ---
misc: uwe5622-allwinner-v6.3.patch
misc: uwe5622-allwinner-bugfix-v6.3.patch
misc: uwe5622-allwinner-v6.3-compilation-fix.patch
misc: uwe5622-v6.1.patch
misc: uwe5622-park-link-v6.1-post.patch
misc: uwe5622-v6.4-post.patch
misc: uwe5622-v6.6-fix-tty-sdio.patch
misc: uwe5622-warnings.patch
gen: uwe5622-wireless-makefile
#
# --- Operator NV12 userpatches (apply last) ---
user: 0099-de33-enable-nv12-vi-plane.patch
user: 0100-cedrus-prefer-linear-nv12.patch
#
# --- Dependency-closure prerequisites added empirically in Task 2 appear below ---
```

Note: replace the two `# ...` lines with the real `patches.drm/*` and `patches.media/*` entries — generate them with:
`ls ~/h618-kernel-work/armbian-build/patch/kernel/archive/sunxi-6.18/patches.drm | sed 's,^,series: patches.drm/,'`
(and likewise for `patches.media`), inserted in `series.conf` order.

- [ ] **Step 2: Write the extraction script**

Create `scripts/extract-kernel-patches.sh`:

```bash
#!/usr/bin/env bash
# Regenerate board/orangepi/zero2w/patches/linux/ from kernel-patches.list.
# Needs an Armbian build tree (only to source the patch files) — NOT a build dependency.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ARMBIAN_BUILD="${ARMBIAN_BUILD:-$HOME/h618-kernel-work/armbian-build}"
SERIES_DIR="$ARMBIAN_BUILD/patch/kernel/archive/sunxi-6.18"
MISC_DIR="$ARMBIAN_BUILD/patch/misc/wireless-uwe5622"
USER_DIR="$ARMBIAN_BUILD/userpatches/kernel/archive/sunxi-6.18"
WT="$ARMBIAN_BUILD/cache/sources/linux-kernel-worktree/6.18__sunxi64__arm64"
MANIFEST="$REPO/board/orangepi/zero2w/kernel-patches.list"
OUT="$REPO/board/orangepi/zero2w/patches/linux"

[ -d "$SERIES_DIR" ] || { echo "ERROR: Armbian tree not found at $ARMBIAN_BUILD (set ARMBIAN_BUILD=)"; exit 1; }
rm -rf "$OUT"; mkdir -p "$OUT"

n=0
while IFS= read -r line; do
	line="${line%%#*}"; line="$(echo "$line" | xargs || true)"   # strip comment + trim
	[ -z "$line" ] && continue
	kind="${line%%:*}"; ref="$(echo "${line#*:}" | xargs)"
	n=$((n+1)); pfx="$(printf '%04d' "$n")"
	case "$kind" in
		series) src="$SERIES_DIR/$ref" ;;
		misc)   src="$MISC_DIR/$ref" ;;
		user)   src="$USER_DIR/$ref" ;;
		gen)
			if [ "$ref" = "uwe5622-wireless-makefile" ]; then
				git -C "$WT" -c safe.directory="$WT" diff "v6.18.35" -- \
					drivers/net/wireless/Makefile > "$OUT/${pfx}-uwe5622-wireless-makefile.patch"
				echo "  $pfx <- gen: uwe5622-wireless-makefile"
				continue
			fi
			echo "ERROR: unknown gen ref '$ref'"; exit 1 ;;
		*) echo "ERROR: bad manifest line: $line"; exit 1 ;;
	esac
	[ -f "$src" ] || { echo "ERROR: missing patch source: $src"; exit 1; }
	cp "$src" "$OUT/${pfx}-$(basename "$ref")"
	echo "  $pfx <- $kind: $ref"
done < "$MANIFEST"

echo "OK: wrote $n patches to $OUT"
```

- [ ] **Step 3: Make it executable and run it (verify it fails cleanly without the tree, then succeeds)**

```bash
chmod +x scripts/extract-kernel-patches.sh
ARMBIAN_BUILD=/nonexistent ./scripts/extract-kernel-patches.sh; echo "exit=$?"   # expect: ERROR + exit=1
./scripts/extract-kernel-patches.sh                                              # expect: "OK: wrote N patches"
ls board/orangepi/zero2w/patches/linux | head
ls board/orangepi/zero2w/patches/linux | wc -l    # expect ~60 (43 drm + 6 media + 1 dts + 9 uwe5622 + 2 user)
```

- [ ] **Step 4: Verify determinism (re-run = identical output)**

```bash
md5sum board/orangepi/zero2w/patches/linux/*.patch | md5sum > /tmp/a
./scripts/extract-kernel-patches.sh
md5sum board/orangepi/zero2w/patches/linux/*.patch | md5sum > /tmp/b
diff /tmp/a /tmp/b && echo "DETERMINISTIC"     # expect: DETERMINISTIC
```

- [ ] **Step 5: Write the provenance README**

Create `board/orangepi/zero2w/patches/linux/README.md`:

```markdown
# Curated kernel patches — Orange Pi Zero 2W (mainline 6.18.35)

Generated from `board/orangepi/zero2w/kernel-patches.list` by
`scripts/extract-kernel-patches.sh` against an Armbian build tree. Applied by
Buildroot via `BR2_GLOBAL_PATCH_DIR` in alphanumeric (= manifest) order.

Do not edit these files by hand — edit the manifest and re-run the script.
The Armbian tree is only needed to (re)generate these; it is NOT a build dependency.
```

- [ ] **Step 6: Commit**

```bash
git add scripts/extract-kernel-patches.sh board/orangepi/zero2w/kernel-patches.list board/orangepi/zero2w/patches/
git commit -m "feat(orangepi-zero2w): manifest-driven kernel-patch extractor + seed subset" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Wire Buildroot to mainline + close the dependency gap (build)

Point Buildroot at pristine 6.18.35 + the curated subset, and grow the manifest until the kernel **compiles**. Keep the existing full `linux.config` (decouple patch-migration from config-trim). Deliverable: a full image built from mainline + the subset, no tarball.

**Files:**
- Modify: `configs/orangepi_zero2w_defconfig` (kernel source lines)
- Modify: `board/orangepi/zero2w/kernel-patches.list` (append prerequisites as discovered)
- Regenerate: `board/orangepi/zero2w/patches/linux/` (via the Task 1 script)

**Interfaces:**
- Consumes: `scripts/extract-kernel-patches.sh`, `kernel-patches.list` (Task 1).
- Produces: a defconfig that builds the kernel with no `.opi-artifacts` input.

- [ ] **Step 1: Switch the defconfig kernel source**

In `configs/orangepi_zero2w_defconfig`, replace the two tarball lines:

```
BR2_LINUX_KERNEL_CUSTOM_TARBALL=y
BR2_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION="file://${BR2_EXTERNAL_OPENIPC_SBC_GS_PATH}/.opi-artifacts/linux-6.18.35-opi-sunxi.tar.gz"
```

with:

```
BR2_LINUX_KERNEL_CUSTOM_VERSION=y
BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="6.18.35"
BR2_GLOBAL_PATCH_DIR="${BR2_EXTERNAL_OPENIPC_SBC_GS_PATH}/board/orangepi/zero2w/patches"
```

Leave `BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG`, `..._CUSTOM_CONFIG_FILE`, `..._INTREE_DTS_NAME`, `..._DTB_KEEP_DIRNAME`, `..._INSTALL_TARGET` unchanged.

- [ ] **Step 2: Apply defconfig + attempt kernel extract/patch/build (expect it to fail in the patch or compile step initially)**

```bash
export REPO=$PWD
BR="make -C buildroot O=$REPO/output/orangepi_zero2w_defconfig BR2_EXTERNAL=$REPO"
$BR orangepi_zero2w_defconfig
$BR linux-dirclean linux 2>&1 | tee /tmp/klog.txt; echo "exit=${PIPESTATUS[0]}"
```
Expected initially: failure during **patch apply** (a `.drm` hunk needs a megous prerequisite) or **compile** (missing symbol). This is the closure gap.

- [ ] **Step 3: Resolve the failure — find the prerequisite and add it to the manifest**

For a patch-apply failure, the log names the failing file/hunk. Find the Armbian patch that provides the missing context and precedes it in `series.conf`:

```bash
# Which series patches touch the file that failed to patch (e.g. drivers/gpu/drm/sun4i/sun4i_tcon.c):
grep -rl "sun4i_tcon" ~/h618-kernel-work/armbian-build/patch/kernel/archive/sunxi-6.18/patches.megous \
                      ~/h618-kernel-work/armbian-build/patch/kernel/archive/sunxi-6.18/patches.armbian
# Confirm its position/order in the authoritative series:
grep -nE "sun4i_tcon|<candidate-filename>" ~/h618-kernel-work/armbian-build/patch/kernel/archive/sunxi-6.18/series.conf
```
Add the prerequisite to `kernel-patches.list` **before** the patch that needed it (respecting `series.conf` relative order), e.g.:
```
series: patches.megous/fixes-6.18/0012-Revert-drm-sun4i-lvds-Invert-the-LVDS-polarity.patch
```

- [ ] **Step 4: Regenerate patches and rebuild; repeat Steps 3–4 until the kernel builds**

```bash
./scripts/extract-kernel-patches.sh
$BR linux-dirclean linux 2>&1 | tee /tmp/klog.txt; echo "exit=${PIPESTATUS[0]}"
```
Loop until `exit=0`. **Exit criterion:** the kernel + DTB + modules compile cleanly. Each added prerequisite should be the *minimal* one that resolves the current failure (prefer `patches.megous`/`patches.armbian` entries that `series.conf` places before the dependent patch).

- [ ] **Step 5: Build the full image from the in-house source**

```bash
DEFCONFIG=orangepi_zero2w_defconfig ./build.sh 2>&1 | tail -20
ls -la output/orangepi_zero2w_defconfig/images/orangepi_zero2w_sdcard.img    # expect: exists, freshly built
# Sanity: kernel + uwe5622 module are present in the staged rootfs:
find output/orangepi_zero2w_defconfig/target/boot -name Image
find output/orangepi_zero2w_defconfig/target/lib/modules -name 'sprdwl_ng.ko*'   # expect: found
```
Expected: image builds; `Image` and `sprdwl_ng.ko` present (proves the UWE5622 subset compiled as a module).

- [ ] **Step 6: Commit**

```bash
git add configs/orangepi_zero2w_defconfig board/orangepi/zero2w/kernel-patches.list board/orangepi/zero2w/patches/
git commit -m "feat(orangepi-zero2w): build kernel from mainline 6.18.35 + curated patch subset" \
           -m "Drop the Armbian-snapshot tarball; Buildroot now fetches pristine 6.18.35 and applies the in-repo curated subset (closure grown until it builds)." \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Boot + feature verification of the in-house image (full config)

Prove the curated subset is *functionally complete*: the in-house-built image behaves identically to the snapshot-built one. This is a hardware gate, distinct from "it compiled."

**Files:** none (verification only; may append prerequisites to `kernel-patches.list` if a feature is missing at runtime).

**Interfaces:**
- Consumes: `output/orangepi_zero2w_defconfig/images/orangepi_zero2w_sdcard.img` (Task 2).

- [ ] **Step 1: Flash the image to SD**

```bash
# Identify the SD device first (lsblk); then, carefully:
sudo dd if=output/orangepi_zero2w_defconfig/images/orangepi_zero2w_sdcard.img of=/dev/sdX bs=4M conv=fsync status=progress
```

- [ ] **Step 2: Boot the board and run the full V1–V5 gate**

Set `BOARD=root@<board-ip>` (password `12345`). Run the V1–V5 commands from **Global Constraints → THE BOOT-VERIFICATION GATE**.
Expected: all five pass — boots as 6.18.35; `wlan0` + `sprdwl_ng`; DE33 HDMI plane via `modetest`; `cedrus` + `/dev/videoN`; storage partitions present.

- [ ] **Step 3: If a runtime feature is missing, add its prerequisite and rebuild**

If the kernel built but a feature is dead at runtime (e.g. no DE33 plane, no `cedrus` node), a runtime-only prerequisite patch is missing. Identify it via `dmesg` errors + `series.conf`, add to `kernel-patches.list`, then:

```bash
./scripts/extract-kernel-patches.sh
export REPO=$PWD; BR="make -C buildroot O=$REPO/output/orangepi_zero2w_defconfig BR2_EXTERNAL=$REPO"
$BR linux-dirclean linux && $BR all
```
Re-flash, re-run V1–V5. Repeat until all pass.

- [ ] **Step 4: Commit (only if the manifest changed in Step 3; otherwise skip)**

```bash
git add board/orangepi/zero2w/kernel-patches.list board/orangepi/zero2w/patches/
git commit -m "fix(orangepi-zero2w): add runtime prerequisite patches for full feature parity" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Trim the kernel config to required modules only

With a known-good in-house image booting, trim the 9,667-line config to what the board actually uses, ground-truthed from the live board. Boot-verify after each trim.

**Files:**
- Modify: `board/orangepi/zero2w/linux.config` (replaced by the trimmed config)

**Interfaces:**
- Consumes: the booting in-house image (Task 3) with `/proc/config.gz` (`CONFIG_IKCONFIG_PROC=y`, confirmed present).

- [ ] **Step 1: Capture ground truth from the running board**

```bash
ssh $BOARD 'zcat /proc/config.gz' > /tmp/board-config.txt
ssh $BOARD 'lsmod' > /tmp/board-lsmod.txt
wc -l board/orangepi/zero2w/linux.config /tmp/board-config.txt   # baseline sizes
cat /tmp/board-lsmod.txt   # the modules that MUST remain (=m), e.g. sprdwl_ng, rtl88x2*, sunxi_addr
```

- [ ] **Step 2: Run localmodconfig in the kernel build dir, seeded by the board's lsmod**

```bash
cd output/orangepi_zero2w_defconfig/build/linux-6.18.35
make ARCH=arm64 \
     CROSS_COMPILE=$PWD/../../host/bin/aarch64-buildroot-linux-gnu- \
     LSMOD=/tmp/board-lsmod.txt localmodconfig
cd $REPO
```
Expected: prompts default-answered; modules not in `lsmod` are disabled. (This trims `=m`; built-ins are pruned manually in Step 3.)

- [ ] **Step 3: Manually prune unneeded built-ins via menuconfig**

```bash
export REPO=$PWD; BR="make -C buildroot O=$REPO/output/orangepi_zero2w_defconfig BR2_EXTERNAL=$REPO"
$BR linux-menuconfig
```
Disable: other SoC families/arches, unused filesystems, debug/tracing, networking protocols not used.
**Keep `=y`** (boot/feature critical — do not disable): `MMC_SUNXI`, `SQUASHFS` + `SQUASHFS_ZSTD`, `PINCTRL_SUN50I_H616*`, `SUNXI` CCU/clk/regulators, `CMA`, `DRM_SUN4I*`/`DRM_SUN8I_DW_HDMI`/`DRM_SUN50I_PLANES`, `VIDEO_SUNXI`/Cedrus, USB host + gadget (OTG), `CFG80211`/`MAC80211`, `AW_WIFI_DEVICE_UWE5622=y`.
**Keep `=m`:** `WLAN_UWE5622`, `RTL8812AU`/`RTL88X2EU`/`RTL88X2CU` (built by Buildroot packages against this kernel — must stay loadable).

- [ ] **Step 4: Persist the trimmed config back to the repo and rebuild**

```bash
$BR linux-update-config       # writes board/orangepi/zero2w/linux.config
$BR linux-reconfigure && $BR all
wc -l board/orangepi/zero2w/linux.config    # expect materially smaller than 9667
```

- [ ] **Step 5: Re-flash and run the full V1–V5 gate**

Flash the new image (Task 3 Step 1 command), boot, run V1–V5 (Global Constraints). All must still pass.
If anything fails, re-enable the responsible symbol via `linux-menuconfig`, `linux-update-config`, rebuild, re-test (bisect the cut).

- [ ] **Step 6: Commit**

```bash
git add board/orangepi/zero2w/linux.config
git commit -m "feat(orangepi-zero2w): trim kernel config to required modules only" \
           -m "localmodconfig seeded from the live board's lsmod + manual built-in prune; boots + display/wifi/cedrus/storage all verified on hardware." \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Remove the Armbian dependency + fix the docs

Delete the now-dead snapshot tooling and document the self-contained build. Final gate: a clean tree with no Armbian inputs still builds.

**Files:**
- Delete: `scripts/prepare-opi-artifacts.sh`
- Modify: `.gitignore` (remove the `.opi-artifacts/` kernel-tarball entry if nothing else needs it)
- Modify: `README.md` (add the board; document the build)

- [ ] **Step 1: Confirm `prepare-opi-artifacts.sh` has no remaining users, then delete it**

```bash
grep -rIn "prepare-opi-artifacts\|opi-artifacts" --exclude-dir=buildroot --exclude-dir=output --exclude-dir=.git . \
  | grep -v "docs/superpowers"
# Expect only the .gitignore line + the script itself. ffmpeg moved to package/ffmpeg-v4l2request already.
git rm scripts/prepare-opi-artifacts.sh
```

- [ ] **Step 2: Drop the `.opi-artifacts` kernel input + its gitignore entry**

```bash
rm -f .opi-artifacts/linux-6.18.35-opi-sunxi.tar.gz
```
Edit `.gitignore`: remove the `.opi-artifacts/` line **only if** `.opi-artifacts/` holds nothing else still in use (check `ls .opi-artifacts/`). If `ffmpeg-v4l2request-*` or other inputs remain, leave the ignore line and just delete the kernel tarball.

- [ ] **Step 3: Update the README**

In `README.md`: add `Orange Pi Zero 2W (Allwinner H618)` to **Supported GS Hardware**, and add a build note under **Custom Build**:

```markdown
The Orange Pi Zero 2W builds fully from source — no external kernel tree is required:

    DEFCONFIG=orangepi_zero2w_defconfig ./build.sh

(The kernel is mainline 6.18.35 plus the curated patch set under
`board/orangepi/zero2w/patches/`. To re-derive that set from an Armbian tree,
see `scripts/extract-kernel-patches.sh`.)
```

- [ ] **Step 4: FINAL GATE — clean-tree build with no Armbian inputs**

```bash
test ! -e .opi-artifacts/linux-6.18.35-opi-sunxi.tar.gz && echo "no kernel tarball: OK"
mv ~/h618-kernel-work ~/h618-kernel-work.hidden    # temporarily hide the Armbian tree
export REPO=$PWD; BR="make -C buildroot O=$REPO/output/orangepi_zero2w_defconfig BR2_EXTERNAL=$REPO"
$BR linux-dirclean
DEFCONFIG=orangepi_zero2w_defconfig ./build.sh 2>&1 | tail -15
ls -la output/orangepi_zero2w_defconfig/images/orangepi_zero2w_sdcard.img   # expect: rebuilt with the tree hidden
mv ~/h618-kernel-work.hidden ~/h618-kernel-work    # restore
```
Expected: the image builds with the Armbian tree absent — proving self-containment.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(orangepi-zero2w): drop Armbian-tree dependency; self-contained kernel build" \
           -m "Delete prepare-opi-artifacts.sh + the .opi-artifacts kernel tarball; README documents the from-source build." \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage:**
- §1 defconfig swap → Task 2 Step 1. ✓
- §2 curated subset + manifest + extraction + empirical closure → Tasks 1 (tooling/seed) + 2 (build closure) + 3 (runtime closure). ✓
- §3 trimmed config (localmodconfig + manual prune, =y/=m policy) → Task 4. ✓
- §4 verification gates → Global Constraints V1–V5, exercised in Tasks 3 & 4. ✓
- §5 repo layout/tooling/cleanup/README → Tasks 1 (layout) + 5 (cleanup/docs). ✓
- §6 risks: fallback baseline = the snapshot build remains until Task 3 passes (Tasks ordered so the tarball/defconfig change is reversible until proven); over-trim bisect → Task 4 Step 5. ✓
- Acceptance criteria 1–5 → Task 5 Step 4 (clean build), Tasks 3–4 (boot/features/smaller config), Task 1 (manifest+script), Task 5 (cleanup). ✓
- "Confirm during impl": initramfs (resolved: none — Global Constraints), `/proc/config.gz` (resolved: present — Task 4), HDMI audio (left out of seed; add `hdmi-audio-6.18` to manifest in Task 3 only if required), kernel hash (no-hash warning accepted; not blocking). ✓

**2. Placeholder scan:** The two `# ...` lines in the Task 1 seed manifest are *expansion instructions with the exact command to generate them*, not unspecified work — acceptable. No "TBD"/"handle errors"/"write tests for the above". ✓

**3. Type/name consistency:** `kernel-patches.list` manifest line kinds (`series:`/`misc:`/`user:`/`gen:`) defined in Task 1 Interfaces and used identically in the seed manifest and the script. `$BR` shorthand, `BOARD`, `REPO`, and `orangepi_zero2w_defconfig`/output paths consistent across all tasks. `extract-kernel-patches.sh` name consistent. ✓

---

## Notes on ordering & reversibility
Tasks 1→2→3 keep the old snapshot build recoverable: Task 2's defconfig edit is a 2-line revert, and the `.opi-artifacts` tarball is not deleted until Task 5 — so if the curated subset can't reach feature parity (Task 3), reverting is trivial. Config trimming (Task 4) only begins once a known-good in-house image exists, so any regression is unambiguously a config cut, not a patch gap.
