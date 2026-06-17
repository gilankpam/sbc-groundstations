include $(sort $(wildcard $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/package/*/*.mk))
ifeq ($(BR2_PACKAGE_HOST_RKDEVELOPTOOL),y)
include $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/board/radxa/zero3/flash.mk
endif

# we don't need cland on target
define CLANG_DELETE_TARGET
	rm -rf $(TARGET_DIR)/usr/include/clang-c \
		$(TARGET_DIR)/usr/include/clang \
		$(TARGET_DIR)/usr/include/clang \
		$(TARGET_DIR)/usr/lib/libclang* \
		$(TARGET_DIR)/usr/lib/cmake/clang* \
		$(TARGET_DIR)/usr/lib/libclang* \
		$(TARGET_DIR)/usr/lib/clang \
		$(TARGET_DIR)/usr/share/man/man1/scan-build.1 \
		$(TARGET_DIR)/usr/bin/diagtool \
		$(TARGET_DIR)/usr/bin/hmaptool \
		$(TARGET_DIR)/usr/bin/analyze-build \
		$(TARGET_DIR)/usr/bin/scan-build-py \
		$(TARGET_DIR)/usr/bin/intercept-build \
		$(TARGET_DIR)/usr/bin/amdgpu-arch \
		$(TARGET_DIR)/usr/bin/nvptx-arch \
		$(TARGET_DIR)/usr/libexec/intercept-cc \
		$(TARGET_DIR)/usr/libexec/analyze-cc \
		$(TARGET_DIR)/usr/libexec/analyze-c++ \
		$(TARGET_DIR)/usr/libexec/intercept-c++ \
		$(TARGET_DIR)/usr/lib/libear \
		$(TARGET_DIR)/usr/lib/libscanbuild \
		$(TARGET_DIR)/usr/lib/cmake
endef
CLANG_POST_INSTALL_TARGET_HOOKS += CLANG_DELETE_TARGET

# We don't nee samba python
#
# Override to disable Python support
SAMBA4_CONF_OPTS += --disable-python

# Clear Python-related variables
SAMBA4_PYTHON = 

# we do not need libclc on target
define LIBCLC_DELETE_TARGET
	rm -rf $(TARGET_DIR)/usr/share/clc
endef
LIBCLC_POST_INSTALL_TARGET_HOOKS += LIBCLC_DELETE_TARGET

# Orange Pi Zero 2W: ffmpeg needs the V4L2 Request API hwaccel (Cedrus). Stock
# ffmpeg 6.1.3 lacks it, so build jernejsk/FFmpeg @ v4l2-request-n7.1 (7.1 +
# v4l2-request) via override-srcdir, which also skips Buildroot's 6.1.3-specific
# ffmpeg patches that would not apply to the 7.1 source.
ifeq ($(BR2_PACKAGE_FFMPEG),y)
# FFMPEG_OVERRIDE_SRCDIR is set in the board override file (board/orangepi/
# zero2w/local.mk) — OVERRIDE_SRCDIR is only honored from BR2_PACKAGE_OVERRIDE_FILE.
FFMPEG_CONF_OPTS += --enable-v4l2-request --enable-v4l2_m2m --enable-libdrm
FFMPEG_DEPENDENCIES += libdrm
# Buildroot's 6.1.3 ffmpeg.mk passes options removed in ffmpeg 7.1 (e.g.
# --disable-crystalhd), which the jernejsk 7.1 source's configure rejects.
# Neutralize die_unknown in the override-rsynced configure so removed options
# are ignored instead of aborting the build.
define FFMPEG_TOLERATE_REMOVED_CONF_OPTS
	$(SED) '/^die_unknown(){/,/^}/ s/exit 1/return 0/' $(@D)/configure
endef
FFMPEG_PRE_CONFIGURE_HOOKS += FFMPEG_TOLERATE_REMOVED_CONF_OPTS
endif
