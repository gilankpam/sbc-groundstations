# mabur ground station as a Buildroot package

Date: 2026-09-10
Status: approved design, not yet implemented

## Purpose

Ship the mabur RTP-free FPV video link on the three RK3566 ground-station
boards in this tree. `maburgs` receives and FEC-decodes the air link and
publishes whole access units to a shm ring; `maburplay` consumes that ring and
drives MPP hardware decode straight to DRM/KMS, with the MSP and GS OSD layers
and the fMP4 DVR on `/media/dvr`.

mabur replaces the entire existing video and link stack on those boards:
wifibroadcast-ng, fpvd, pixelpilot, msposd and adaptive-link all go away
together, and with them their graphics and data dependencies. The image gets
markedly smaller as a result.

## Scope

Three boards move to mabur, all of them RK3566 with the same kernel tarball,
the same `radxa-zero-3-rk3566` U-Boot defconfig and the same DTS list:

- `radxa_zero3_defconfig`
- `runcam_wifilink_defconfig`
- `emax_wyvern-link_defconfig`

Two boards are untouched and keep the old stack:

- `openipc_bonnet_defconfig`
- `orangepi_zero2w_defconfig`

Because those two still build against them, no `package/` directory is deleted
and no line is removed from `Config.in`. Packages leave the three mabur boards
by being switched off in their defconfigs, not by being removed from the tree.

## Upstream pins

| Package | Repository | Commit |
|---|---|---|
| mabur | `https://github.com/gilankpam/mabur.git` | `7dfce0062c735cf525c58091a5678cde602d89b0` |
| devourer | `https://github.com/gilankpam/devourer.git` | `3b15c7ae8dc0fe3608ed42a95750a1b4eb605704` |

Both are the `master` head of their fork as of this date. Bump the hash in the
`.mk` to advance, the same convention the pixelpilot and fpvd packages already
use in this tree.

## Package: devourer

`package/devourer/` — a source-only `generic-package`.

devourer is not a library mabur links against; mabur's top-level
`CMakeLists.txt` pulls it in with
`add_subdirectory(${DEVOURER_DIR} ... EXCLUDE_FROM_ALL)`, so what mabur needs
is the *source tree on disk* at configure time. This package exists to make
Buildroot fetch and extract that tree, and nothing else:

- `DEVOURER_BUILD_CMDS`, `DEVOURER_CONFIGURE_CMDS` and
  `DEVOURER_INSTALL_TARGET_CMDS` are all empty.
- `DEVOURER_INSTALL_STAGING = NO`, `DEVOURER_INSTALL_TARGET = NO`.
- `DEVOURER_DEPENDENCIES = libusb` — devourer's CMake does
  `pkg_check_modules(libusb REQUIRED IMPORTED_TARGET libusb-1.0)`, and that
  resolves during *mabur's* configure step, so libusb must be staged first.

`BR2_PACKAGE_DEVOURER` is not offered as a user-visible menu entry; it is
`select`ed by `BR2_PACKAGE_MABUR`.

Naming the package `devourer` is deliberate. Buildroot's package
infrastructure generates `DEVOURER_DIR = $(BUILD_DIR)/devourer-$(DEVOURER_VERSION)`,
and that is exactly the cache variable mabur's CMake expects, so mabur.mk can
pass `-DDEVOURER_DIR=$(DEVOURER_DIR)` with no path arithmetic of its own. The
reference is inside a recipe body, so it expands at recipe-run time and does
not depend on `external.mk`'s include order.

## Package: mabur

`package/mabur/` — a `cmake-package`.

```
MABUR_DEPENDENCIES = devourer libusb rockchip-mpp libdrm
```

`BR2_PACKAGE_MABUR` selects `BR2_PACKAGE_DEVOURER`, `BR2_PACKAGE_LIBUSB`,
`BR2_PACKAGE_ROCKCHIP_MPP` and `BR2_PACKAGE_LIBDRM`, and depends on
`BR2_INSTALL_LIBSTDCPP` and `BR2_TOOLCHAIN_HAS_THREADS` (mabur is C++20).

Note there is no libgpiod dependency. maburplay's record button drives
`<linux/gpio.h>` ioctls directly — `gs/player/src/rec_button.h` says so in as
many words — so mabur links nothing for it. The boards keep `libgpiod-tools`
anyway, because `gpioinfo` is how you map a header pin to the kernel line name
that `[input.rec] pin` resolves against.

### Configure options

Mirroring `tools/build-arm64.sh`, which is the reference build for this target:

```
-DMABUR_BUILD_DRONE=OFF        # maburd is SigmaStar/armv7, not this image
-DMABUR_BUILD_TESTS=OFF        # host suite, needs GoogleTest
-DMABUR_BUILD_LINKBENCH=OFF    # bench tools are not shipped
-DMABUR_BUILD_GS=ON
-DMABUR_PLAYER_HW=ON
-DDEVOURER_DIR=$(DEVOURER_DIR)
-DDEVOURER_LOG_MAX_LEVEL=WARN
```

Per-chip devourer gates: `DEVOURER_JAGUAR3_8822E=ON`, every other
`DEVOURER_<chip>` explicitly `OFF`. The list must be explicit rather than
inherited: a devourer option defaults to `ON`, so a chip added upstream opts
itself into this build on the next hash bump and silently inflates the binary.
This is the `DEVOURER_8733B` footgun already recorded in mabur's own build
scripts.

`-DBUILD_SHARED_LIBS=OFF` is load-bearing. Buildroot's cmake-package passes
`BUILD_SHARED_LIBS=ON` for anything but a `BR2_STATIC_LIBS` build, and
devourer's `add_library(devourer ...)` names neither STATIC nor SHARED, so it
honours that and emits an unversioned `libdevourer.so`. `package/devourer`
installs nothing to the target by design, so maburgs linked against a library
that was never shipped and died at startup with `error while loading shared
libraries: libdevourer.so`. Every library mabur declares itself is explicitly
STATIC, so forcing this off touches only devourer — and links it in exactly as
mabur's own cross build does. Our `-D` follows Buildroot's on the command line,
so it wins.

`bench/encosd` is *not* skipped by `MABUR_BUILD_LINKBENCH=OFF` — mabur's
top-level CMake gates it on `MABUR_BUILD_GS`, and its own CMakeLists only
returns early when `MABUR_PLAYER_HW` is off, which it is not here. So it gets
built and simply not installed. It links the same `librockchip_mpp.a` path as
maburplay, so the shim below covers it.

### The mpp/drm link shim

`gs/player/CMakeLists.txt` links two libraries by absolute path:

```cmake
target_link_libraries(maburplay PRIVATE
  "${MABUR_MPP_ROOT}/lib/librockchip_mpp.a"
  "${MABUR_DRM_ROOT}/lib/libdrm.a"
  pthread)
```

That shape comes from mabur's own musl-static cross build, where both
libraries really are static archives staged under `toolchain/`. Buildroot
stages them differently: `rockchip-mpp`'s CMake installs a genuine
`librockchip_mpp.a` next to the shared object, but `libdrm` is a Meson package
built shared-only, so `libdrm.a` does not exist in staging.

A pre-configure hook builds a small prefix that satisfies both cache variables
without patching mabur and without turning on `BR2_SHARED_STATIC_LIBS`
globally:

```
$(@D)/br-libs/include               -> $(STAGING_DIR)/usr/include
$(@D)/br-libs/lib/librockchip_mpp.a -> $(STAGING_DIR)/usr/lib/librockchip_mpp.so
$(@D)/br-libs/lib/libdrm.a          -> $(STAGING_DIR)/usr/lib/libdrm.so
```

Both `MABUR_MPP_ROOT` and `MABUR_DRM_ROOT` point at `br-libs`.

Both `.a` names are symlinks to the *shared* objects. `ld` identifies an input
file by its contents, not its extension, so given those paths it links
dynamically and records `libdrm.so.2` and `librockchip_mpp.so.1` as
`DT_NEEDED`. The `.mk` carries this explanation in a comment; anyone who later
makes mabur able to link `-lrockchip_mpp -ldrm` from the sysroot directly
should delete the hook.

Pointing the mpp entry at the shared object, rather than at the genuine
`librockchip_mpp.a` that rockchip-mpp does stage, is a deliberate size call
measured on the first build. Buildroot installs `librockchip_mpp.so.0`
(8.9 MB) to the target regardless, and with pixelpilot gone maburplay is its
only possible consumer. Static-linking left that 8.9 MB on the rootfs with
nothing referencing it *and* carried a second copy of the used objects inside
the binary: `maburplay` measured 2 074 312 bytes static versus 520 680 bytes
shared. The staged `.a` never reaches the image either way — `target-finalize`
deletes `*.a` from the target.

The header side needs no shim. mabur includes `<rockchip/rk_mpi.h>` and
staging has `usr/include/rockchip/`; it includes `<xf86drm.h>` and
`<drm_fourcc.h>`, and mabur already adds both `${MABUR_DRM_ROOT}/include` and
`${MABUR_DRM_ROOT}/include/libdrm`, which staging provides at exactly those
two levels.

### GPIO v2 uAPI compatibility header

`gs/player/src/rec_button.cpp` speaks the v2 GPIO character-device uAPI
directly — `gpio_v2_line_request`, `GPIO_V2_GET_LINE_IOCTL` and friends — which
landed in Linux 5.10. Every aarch64 external toolchain Buildroot offers ships
older sysroot headers on purpose, so binaries stay runnable on old kernels: the
ARM AArch64 toolchain these boards default to declares
`BR2_TOOLCHAIN_HEADERS_AT_LEAST_4_20`, and Bootlin's aarch64 glibc toolchain
only guarantees 5.4. Neither has v2, so the file does not compile — this is the
one thing that actually broke on the first build attempt.

Switching toolchains does not fix it, and it does not need fixing at runtime:
these boards run a 6.1 kernel that implements v2. Only the compile-time
declarations are missing, and the uAPI is stable ABI.

`package/mabur/gpio_v2_compat.h` supplies them, copied verbatim from the target
kernel's own `include/uapi/linux/gpio.h` and stopping before the deprecated v1
ABI, which the old sysroot header already defines. `mabur.mk` force-includes it
into every translation unit:

```
MABUR_GPIO_COMPAT_FLAG = -include $(MABUR_PKGDIR)/gpio_v2_compat.h
MABUR_CONF_OPTS = \
	-DCMAKE_C_FLAGS="$(TARGET_CFLAGS) $(MABUR_GPIO_COMPAT_FLAG)" \
	-DCMAKE_CXX_FLAGS="$(TARGET_CXXFLAGS) $(MABUR_GPIO_COMPAT_FLAG)" \
	...
```

Prepending `$(TARGET_CFLAGS)`/`$(TARGET_CXXFLAGS)` is mandatory, not tidiness:
Buildroot's `toolchainfile.cmake` sets the flags only `if(NOT DEFINED
CMAKE_C_FLAGS)`, so passing `-DCMAKE_C_FLAGS` at all takes ownership of them.
That file's own comments document this as the intended override path.

The whole header is guarded on `GPIO_V2_GET_LINE_IOCTL`, so it goes inert the
moment a toolchain ships v2, at which point both it and the `-include` flag can
be deleted. The durable fix belongs upstream in mabur: an equivalent `#ifndef`
fallback in `rec_button.cpp` would make it build against any toolchain.

### Install layout

mabur declares no `install()` rules — its own deploy scripts copy artifacts by
hand — so `MABUR_INSTALL_TARGET_CMDS` is explicit.

| Source | Target |
|---|---|
| `maburgs` | `/usr/local/bin/maburgs` |
| `maburplay` | `/usr/local/bin/maburplay` |
| `gs/player/bundle/font_btfl.mfont` | `/usr/local/share/mabur/font_btfl.mfont` |
| `gs/player/bundle/gs_osd.gfont` | `/usr/local/share/mabur/gs_osd.gfont` |
| `gs/player/bundle/splash.bin` | `/usr/local/share/mabur/splash.bin` |
| `tools/maburtop.py` | `/usr/bin/maburtop` |
| `gs/bundle/S96maburgs` | `/etc/init.d/S96maburgs` |
| `gs/player/bundle/S97maburplay` | `/etc/init.d/S97maburplay` |
| `gs/bundle/maburgs.default.toml` | `/etc/maburgs.toml` |
| `gs/player/bundle/maburplay.default.toml` | `/etc/maburplay.toml` |

The three runtime assets are not optional and not linked into the binaries.
`maburplay.toml` names `/usr/local/share/mabur/font_btfl.mfont` and
`gs_osd.gfont` directly, and `splash.bin` is hardcoded in `splash_image.h`
with no config key. They total about 29 MB uncompressed, 13 MB of that the GS
OSD atlas, which bakes a coverage+shadow mask at all 30 sizes the responsive
layout can request across 720p–2160p. The squashfs is zstd-compressed and the
packages being removed are far larger, so the image still shrinks.

`maburtop.py` goes to `/usr/bin`, not `/usr/local/bin`: the GS shell's default
`PATH` does not include `/usr/local/bin`. It imports only the standard library
(`argparse`, `curses`, `json`, `socket`, `time`), so `BR2_PACKAGE_PYTHON3` plus
`BR2_PACKAGE_PYTHON3_CURSES` is the whole requirement.

The two init scripts come from mabur's own bundles unmodified. `S96maburgs`
runs `rmmod 8812eu` on start so devourer can claim the cards over libusb;
that becomes a no-op once the Realtek kernel drivers are dropped, and it is
kept because it is upstream's file.

## Per-board `maburplay.toml`

The package installs mabur's `maburplay.default.toml` as `/etc/maburplay.toml`.
Each of the three boards then overrides it from its rootfs overlay, because
Buildroot applies overlays after package installation:

```
board/radxa/zero3/overlay/etc/maburplay.toml
board/runcam/wifilink/overlay/etc/maburplay.toml
board/emax/wyvern-link/overlay/etc/maburplay.toml
```

This is required, not cosmetic. `[input.rec] pin = 32` in mabur's default is a
Radxa header pin, and `emax_wyvern-link_defconfig` sets
`BR2_FACTORY_RESET_GPIO_PIN_NAME="PIN_32"` — shipping the default to emax would
wire maburplay's DVR record button to the factory-reset button. Pin 32 is free
on radxa (11/13) and runcam (38/13), so those two overlays start as copies of
the default; emax's drops or relocates the `[input.rec]` block.

Giving all three an overlay rather than only emax means each board's display
and record-button configuration is visible and pinned in this repo, instead of
two of them silently tracking whatever mabur's default TOML becomes.

`/etc/maburgs.toml` is board-independent (radio, FEC, ladder) and is left to
the package.

## Defconfig changes

Applied to all three mabur boards.

### Enabled

- `BR2_PACKAGE_MABUR=y`
- `BR2_PACKAGE_LIBUSB=y` on runcam and emax. Both are missing it; radxa
  already has it. devourer does not build without it.

### Removed: the replaced stack

`wifibroadcast-ng`, `wfb-server`, `fpvd`, `pixelpilot`, `msposd`,
`adaptive-link`, `dvrui`, `yaml-cli`, `librga`.

emax additionally has `go2rtc`, `gstreamer-tee` and `openipc-gs-web` enabled;
those go too.

### Removed: dependencies of the replaced stack

Graphics — `gstreamer1` and every `gst1-plugins-*` entry, `mesa3d` with its
`_LLVM`, `_GALLIUM_DRIVER_PANFROST`, `_OPENGL_EGL` and `_OPENGL_ES` options,
`mali-driver-custom`, `cairo-png`, `cairomm`. maburplay talks to DRM/KMS and
MPP directly and needs no GL stack at all.

Data — `json-for-modern-cpp`, `yaml-cpp`, `spdlog`, `msgpack`, `cjson`. No
package remaining in these three configs references them.

Python modules — `flask`, `twisted`, `pyroute2`, `babel`, `python-msgpack`,
`pyyaml`, `serial`. The interpreter and `python3-curses` stay for maburtop.

### Removed: Realtek kernel drivers

`rtl8812au`, `rtl88x2cu`, `rtl88x2eu`.

devourer drives the cards from userspace over libusb, and a bound kernel
driver is actively harmful here: it re-binds the interface after devourer's
USB reset. Removing the modules is the durable version of `S96maburgs`'s
`rmmod 8812eu`.

### Removed: redundant userland

`samba4`, `openssh`, `ntp`, `libcurl` (with `libcurl-curl`).

dropbear already provides sshd and the legacy-protocol scp path mabur's own
install scripts use. busybox provides ntpd. Dropping libcurl disables
`sysupgrade -u -r` online update; upgrading from a `.tar.gz` on the SD or DVR
partition is unaffected.

### Explicitly kept

- `autofs` and the SD-card udev rules. `auto.master` routes `/media` through
  `auto-dvr.sh`, and that is what mounts `/media/dvr` — where maburplay writes
  DVR recordings (`dvr.dir`) and maburgs writes its debug-log session
  directories (`debug_log.dir = /media/dvr/log`). Only the SMB export was
  dropped, not the mount.
- `wpa_supplicant` with AP support, `dnsmasq`, `aic8800`.
  `board/common/overlay/etc/network/interfaces.d/wlan0` puts `wlan0` at
  **10.18.0.1** with the hotspot config — that is the operator's SSH path to
  the ground station. Removing it would cut access to the device.
- Gadget mode. `post-build-script.sh` wires `/usr/sbin/gadget init` into
  `inittab` for every board in this tree.
- `fbv`. `board/common/overlay/init` uses it for the initramfs boot splash,
  which is separate from maburplay's own `splash.bin`.
- `libgpiod` and its tools. Not a mabur dependency (see above), but
  `gpioinfo` is how you resolve a header pin to a kernel line name when
  setting `[input.rec] pin`.
- `drm_info` and the shell conveniences: `htop`, `coreutils`, `file`, `socat`,
  `netcat`, `lrzsz`, `jq`, `sshpass`, `xz`, `parted`, `dosfstools`,
  `e2fsprogs-resize2fs`.

## Overlay cleanup

Deleted, one per mabur board:

```
board/radxa/zero3/overlay/etc/pixelpilot.yaml
board/runcam/wifilink/overlay/etc/pixelpilot.yaml
board/emax/wyvern-link/overlay/etc/pixelpilot.yaml
```

`board/common/overlay/etc/pixelpilot/osd.json` and
`board/common/overlay/etc/go2rtc/go2rtc.yaml` stay. They are shared with
`openipc_bonnet` and `orangepi_zero2w`, which still run that stack.

## sysupgrade

`board/common/overlay/sbin/sysupgrade`'s `free_resources()` stops
`S99pixelpilot`, `S98adaptive-link` and `S98msposd` unconditionally. On a mabur
image those files do not exist, and more importantly maburplay would keep
holding the DRM master while the rootfs is swapped.

Guard the three existing lines with `[ -x … ] &&` and add `S97maburplay` and
`S96maburgs` the same way. The guards make the file correct on all five
boards, so editing this shared file does not regress the two that keep the old
stack.

## Verification

- `DEFCONFIG=radxa_zero3_defconfig ./build.sh` completes, via `shell.nix` on
  this NixOS host.

  Two traps. First, `nix-shell --run '...'` silently does nothing against this
  `shell.nix` — `buildFHSEnv`'s `.env` swallows `--run`, exits 0, and produces
  no output, so the README's invocation looks like an instant success. Feed the
  command on stdin instead: `echo '...' | nix-shell shell.nix`. Second, even
  then the wrapper's exit status does not reflect the build's, so **read the
  log**; a failed build still reports 0.
- The same for `runcam_wifilink_defconfig` and `emax_wyvern-link_defconfig`.
- Inspect `output/<board>/target/` for the install layout in the table above:
  both binaries, all three assets, both init scripts, both TOMLs, `maburtop`.
- Resolve **every** `NEEDED` entry of **both** binaries against the rootfs, not
  just maburplay's:

  ```
  readelf -d target/usr/local/bin/{maburgs,maburplay} | grep NEEDED
  ```

  Checking only maburplay is what let the missing `libdevourer.so` reach
  hardware: the shim comment was about libdrm/mpp, so that is all that got
  verified, while maburgs was the binary that broke. Better still, sweep the
  whole rootfs — every ELF under `bin`, `sbin` and `lib` — for `NEEDED` entries
  with no matching `*.so*` in `target/{lib,usr/lib}`. That sweep is cheap and
  is the natural guard for a change that removes ~50 packages; it must report
  zero.
- Confirm the per-board `/etc/maburplay.toml` in the target tree is the board
  overlay's copy and not the package default, and that emax's does not claim
  pin 32.
- Compare rootfs image size against a `master` build of the same board.

Out of scope: flashing, and any on-air or flight verification. The deliverable
is a clean build with a correct install layout, not hardware-verified
behaviour.

## Known limitations

- The `libdrm.a` symlink is a deliberate abuse of linker file-type detection.
  It is contained in one hook in `package/mabur/mabur.mk` and commented there.
- `maburgs.toml`'s radio settings (channel 136, `symbol_size = 332`) must match
  the drone. The package ships mabur's defaults; a mismatched pair has no
  control link and no video.
- Advancing either pinned hash is a flag day across drone and ground station
  whenever the wire format moved, which mabur's own policy allows freely.
