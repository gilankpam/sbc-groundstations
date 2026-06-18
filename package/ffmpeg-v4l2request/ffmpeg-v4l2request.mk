################################################################################
#
# ffmpeg-v4l2request
#
# FFmpeg 7.1 with the out-of-tree V4L2 Request hwaccel (jernejsk fork), for
# Cedrus (H618) hardware HEVC decode. Stock Buildroot ffmpeg is 6.1.3 and lacks
# --enable-v4l2-request, and its 6.1.3 patches do not apply to 7.1 — so this is a
# standalone package rather than an override of the core ffmpeg.
#
################################################################################

FFMPEG_V4L2REQUEST_VERSION = 904a85173fab816bb3c30652300efa93f2333657
FFMPEG_V4L2REQUEST_SITE = https://github.com/jernejsk/FFmpeg.git
FFMPEG_V4L2REQUEST_SITE_METHOD = git
FFMPEG_V4L2REQUEST_LICENSE = GPL-2.0+
FFMPEG_V4L2REQUEST_LICENSE_FILES = COPYING.GPLv2
FFMPEG_V4L2REQUEST_INSTALL_STAGING = YES
# linux: the V4L2 Request UAPI is newer than the toolchain headers, so install
# the board kernel's UAPI and point ffmpeg's includes at it (hook below).
FFMPEG_V4L2REQUEST_DEPENDENCIES = host-pkgconf libdrm udev zlib linux

define FFMPEG_V4L2REQUEST_INSTALL_KERNEL_UAPI
	$(MAKE) -C $(LINUX_DIR) ARCH=arm64 INSTALL_HDR_PATH=$(@D)/kuapi headers_install
endef
FFMPEG_V4L2REQUEST_PRE_CONFIGURE_HOOKS += FFMPEG_V4L2REQUEST_INSTALL_KERNEL_UAPI

# ffmpeg's configure is bespoke (not autotools); mirror Buildroot's core ffmpeg
# cross-compile invocation, with only the options this board needs.
define FFMPEG_V4L2REQUEST_CONFIGURE_CMDS
	(cd $(@D) && rm -rf config.cache && \
	$(TARGET_CONFIGURE_OPTS) \
	./configure \
		--enable-cross-compile \
		--cross-prefix=$(TARGET_CROSS) \
		--sysroot=$(STAGING_DIR) \
		--host-cc="$(HOSTCC)" \
		--arch=$(BR2_ARCH) \
		--target-os=linux \
		--disable-stripping \
		--pkg-config="$(PKG_CONFIG_HOST_BINARY)" \
		--prefix=/usr \
		--enable-shared \
		--disable-static \
		--enable-gpl \
		--enable-v4l2-request \
		--enable-v4l2_m2m \
		--enable-libdrm \
		--enable-libudev \
		--enable-swscale \
		--enable-network \
		--disable-doc \
		--disable-ffplay \
		--disable-ffprobe \
		--extra-cflags=-I$(@D)/kuapi/include \
	)
endef

define FFMPEG_V4L2REQUEST_BUILD_CMDS
	$(MAKE) -C $(@D)
endef

define FFMPEG_V4L2REQUEST_INSTALL_STAGING_CMDS
	$(MAKE) -C $(@D) DESTDIR=$(STAGING_DIR) install
endef

define FFMPEG_V4L2REQUEST_INSTALL_TARGET_CMDS
	$(MAKE) -C $(@D) DESTDIR=$(TARGET_DIR) install
endef

$(eval $(generic-package))
