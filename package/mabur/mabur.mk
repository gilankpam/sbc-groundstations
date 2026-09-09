################################################################################
#
# mabur
#
################################################################################

# gilankpam/mabur master. Bump this hash to advance; keep it in step with the
# devourer hash in package/devourer/devourer.mk, which it is built against.
MABUR_VERSION = 7dfce0062c735cf525c58091a5678cde602d89b0
MABUR_SITE = https://github.com/gilankpam/mabur.git
MABUR_SITE_METHOD = git
MABUR_INSTALL_STAGING = NO
MABUR_INSTALL_TARGET = YES

# devourer supplies the source tree mabur's CMake add_subdirectory()s; the rest
# are real link/staging dependencies, and rockchip-mpp and libdrm additionally
# have to be staged before the pre-configure hook below runs.
#
# No libgpiod: maburplay's record button talks to <linux/gpio.h> ioctls
# directly (gs/player/src/rec_button.cpp), deliberately, so mabur links nothing
# for it. The boards still enable libgpiod-tools for `gpioinfo`, which is how
# you find the line name for a given header pin.
MABUR_DEPENDENCIES = devourer libusb rockchip-mpp libdrm

# gs/player/CMakeLists.txt links two libraries by absolute path:
#
#   ${MABUR_MPP_ROOT}/lib/librockchip_mpp.a
#   ${MABUR_DRM_ROOT}/lib/libdrm.a
#
# That shape is inherited from mabur's own musl-static cross build
# (tools/build-arm64.sh), where both really are static archives staged under
# toolchain/. Buildroot stages them differently: rockchip-mpp's CMake does
# install a genuine librockchip_mpp.a next to the shared object, but libdrm is
# a Meson package built shared-only, so libdrm.a does not exist in staging.
#
# Rather than patch mabur or turn on BR2_SHARED_STATIC_LIBS for the whole
# build, stage one small prefix that satisfies both cache variables. Both .a
# entries are symlinks to the *shared* objects: ld identifies an input file by
# its contents, not its extension, so it links dynamically and records
# libdrm.so.2 / librockchip_mpp.so.1 as DT_NEEDED. Verify with
# `readelf -d .../usr/local/bin/maburplay`.
#
# Pointing the mpp entry at the shared object rather than the real
# librockchip_mpp.a that rockchip-mpp does stage is deliberate. Buildroot
# installs librockchip_mpp.so.0 (~8.9 MB) to the target no matter what, and
# with pixelpilot gone maburplay is its only possible consumer -- static
# linking would leave that 8.9 MB on the rootfs with nothing referencing it
# AND carry a second copy of the used objects inside the binary. (The staged
# .a itself never reaches the image; target-finalize deletes *.a.)
#
# The header side needs no shim. mabur includes <rockchip/rk_mpi.h> and staging
# has usr/include/rockchip/; it includes <xf86drm.h> and <drm_fourcc.h>, and it
# already adds both ${ROOT}/include and ${ROOT}/include/libdrm, which staging
# provides at exactly those two levels.
#
# Delete this hook if mabur ever learns to link -lrockchip_mpp -ldrm from the
# sysroot directly.
define MABUR_STAGE_LIBS
	mkdir -p $(@D)/br-libs/lib
	ln -sfn $(STAGING_DIR)/usr/include $(@D)/br-libs/include
	ln -sfn $(STAGING_DIR)/usr/lib/librockchip_mpp.so \
		$(@D)/br-libs/lib/librockchip_mpp.a
	ln -sfn $(STAGING_DIR)/usr/lib/libdrm.so $(@D)/br-libs/lib/libdrm.a
endef
MABUR_PRE_CONFIGURE_HOOKS += MABUR_STAGE_LIBS

# Mirrors tools/build-arm64.sh, the reference cross build for this target.
# maburd is SigmaStar/armv7 and never built here; the host test suite needs
# GoogleTest; the linkbench/txagcbench tools are not shipped.
#
# The per-chip devourer gates are listed exhaustively on purpose: every
# DEVOURER_<chip> option defaults to ON, so a chip added upstream would opt
# itself into this build on the next hash bump and silently inflate the binary.
# maburplay's record button speaks the v2 GPIO uAPI (Linux 5.10+), which the
# aarch64 external toolchains ship no headers for -- see the long note in
# package/mabur/gpio_v2_compat.h. Force-include the guarded fallback so
# rec_button.cpp compiles; it is inert once the toolchain catches up.
# Prepending $(TARGET_CFLAGS)/$(TARGET_CXXFLAGS) is required, not optional:
# Buildroot's toolchainfile.cmake sets the flags only `if(NOT DEFINED
# CMAKE_C_FLAGS)`, so passing -DCMAKE_C_FLAGS at all takes ownership of them.
# This is the override path that file documents in its own comments.
MABUR_GPIO_COMPAT_FLAG = -include $(MABUR_PKGDIR)/gpio_v2_compat.h

MABUR_CONF_OPTS = \
	-DCMAKE_C_FLAGS="$(TARGET_CFLAGS) $(MABUR_GPIO_COMPAT_FLAG)" \
	-DCMAKE_CXX_FLAGS="$(TARGET_CXXFLAGS) $(MABUR_GPIO_COMPAT_FLAG)" \
	-DMABUR_BUILD_DRONE=OFF \
	-DMABUR_BUILD_TESTS=OFF \
	-DMABUR_BUILD_LINKBENCH=OFF \
	-DMABUR_BUILD_GS=ON \
	-DMABUR_PLAYER_HW=ON \
	-DMABUR_MPP_ROOT=$(@D)/br-libs \
	-DMABUR_DRM_ROOT=$(@D)/br-libs \
	-DDEVOURER_DIR=$(DEVOURER_SRCDIR) \
	-DDEVOURER_LOG_MAX_LEVEL=WARN \
	-DDEVOURER_JAGUAR1=OFF \
	-DDEVOURER_8814=OFF \
	-DDEVOURER_JAGUAR2_8822B=OFF \
	-DDEVOURER_JAGUAR2_8821C=OFF \
	-DDEVOURER_JAGUAR3_8822C=OFF \
	-DDEVOURER_JAGUAR3_8822E=ON \
	-DDEVOURER_8733B=OFF \
	-DDEVOURER_KESTREL_8852B=OFF \
	-DDEVOURER_KESTREL_8852C=OFF

# mabur declares no install() rules -- its own deploy scripts copy artifacts by
# hand -- so the layout is spelled out here.
#
# The three assets under /usr/local/share/mabur are runtime files, not linked-in
# blobs: maburplay.toml names font_btfl.mfont and gs_osd.gfont by path, and
# splash.bin is hardcoded in splash_image.h with no config key.
#
# maburtop goes to /usr/bin, not /usr/local/bin: the GS shell's default PATH
# does not include /usr/local/bin. It imports only the standard library, so
# python3 + python3-curses is the whole requirement.
define MABUR_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(MABUR_BUILDDIR)/gs/maburgs \
		$(TARGET_DIR)/usr/local/bin/maburgs
	$(INSTALL) -D -m 0755 $(MABUR_BUILDDIR)/gs/player/maburplay \
		$(TARGET_DIR)/usr/local/bin/maburplay

	$(INSTALL) -D -m 0644 $(@D)/gs/player/bundle/font_btfl.mfont \
		$(TARGET_DIR)/usr/local/share/mabur/font_btfl.mfont
	$(INSTALL) -D -m 0644 $(@D)/gs/player/bundle/gs_osd.gfont \
		$(TARGET_DIR)/usr/local/share/mabur/gs_osd.gfont
	$(INSTALL) -D -m 0644 $(@D)/gs/player/bundle/splash.bin \
		$(TARGET_DIR)/usr/local/share/mabur/splash.bin

	$(INSTALL) -D -m 0755 $(@D)/tools/maburtop.py \
		$(TARGET_DIR)/usr/bin/maburtop

	$(INSTALL) -D -m 0644 $(@D)/gs/bundle/maburgs.default.toml \
		$(TARGET_DIR)/etc/maburgs.toml
	$(INSTALL) -D -m 0644 $(@D)/gs/player/bundle/maburplay.default.toml \
		$(TARGET_DIR)/etc/maburplay.toml
endef

# Both wrappers are mabur's own bundled files, installed unmodified.
# S96maburgs' start does `rmmod 8812eu` so devourer can claim the cards over
# libusb; that is a no-op here because the mabur boards drop the Realtek kernel
# drivers entirely, and it is kept because it is upstream's file.
#
# The board's own /etc/maburplay.toml comes from its rootfs overlay, which
# Buildroot applies after package installation and which therefore wins over
# the default seeded above. See board/*/overlay/etc/maburplay.toml.
define MABUR_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(@D)/gs/bundle/S96maburgs \
		$(TARGET_DIR)/etc/init.d/S96maburgs
	$(INSTALL) -D -m 0755 $(@D)/gs/player/bundle/S97maburplay \
		$(TARGET_DIR)/etc/init.d/S97maburplay
endef

$(eval $(cmake-package))
