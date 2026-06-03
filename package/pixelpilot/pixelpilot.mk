###############################################################################
#
# pixelpilot
#
###############################################################################

# feat/refactor_ui HEAD (gsmenu refactor, PP_SCALE UI scaling).
# Bump this hash to advance the branch.
PIXELPILOT_VERSION=d7f702e30b5319d1ded35a7aebd4c3cafd4fafb8
PIXELPILOT_SITE=https://github.com/gilankpam/PixelPilot_rk.git
PIXELPILOT_SITE_METHOD = git
PIXELPILOT_GIT_SUBMODULES = YES
PIXELPILOT_INSTALL_STAGING = NO
PIXELPILOT_INSTALL_TARGET = YES
PIXELPILOT_DEPENDENCIES = rockchip-mpp librga mali-driver-custom mesa3d libdrm cairo spdlog json-for-modern-cpp yaml-cpp libgpiod gstreamer1 gst1-plugins-base gst1-plugins-good msgpack

PIXELPILOT_CMAKE_OPTS += -DCMAKE_PREFIX_PATH=$(STAGING_DIR)/usr

# Stock launch chain (init script + respawn wrapper). pixelpilot stays
# standalone-bootable. When BR2_PACKAGE_FPVD is enabled, fpvd supervises
# pixelpilot directly and retires these in its post-install hook -- see
# package/fpvd/fpvd.mk.
define PIXELPILOT_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/package/pixelpilot/files/S99pixelpilot \
		$(TARGET_DIR)/etc/init.d/S99pixelpilot

	$(INSTALL) -D -m 0755 $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/package/pixelpilot/files/pixelpilot.sh \
		$(TARGET_DIR)/usr/bin/pixelpilot.sh
endef

define PIXELPILOT_POST_INSTALL_TARGET_HOOK
	mkdir -p $(TARGET_DIR)/etc/default
	mkdir -p $(TARGET_DIR)/etc/pixelpilot
	mkdir -p $(TARGET_DIR)/usr/share/fonts

	# Stock env/args for the launch chain (sourced by pixelpilot.sh). fpvd
	# retires this alongside the init script when BR2_PACKAGE_FPVD is enabled.
	$(INSTALL) -D -m 0644 $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/package/pixelpilot/files/pixelpilot \
		$(TARGET_DIR)/etc/default/pixelpilot

	# gsmenu.sh is intentionally NOT installed -- the old shell menu launcher is
	# superseded by the in-binary gsmenu UI (feat/refactor_ui). Unrelated to the
	# fpvd handoff.
	# $(INSTALL) -D -m 0755 $(PIXELPILOT_PKGDIR)/files/gsmenu.sh \
	# 	$(TARGET_DIR)/usr/bin/gsmenu.sh

	# Roboto: OSD font, selected by family name via Cairo/fontconfig
	# (src/osd.cpp). Must live under a fontconfig-scanned dir.
	$(INSTALL) -D -m 0644 $(PIXELPILOT_PKGDIR)/files/Roboto-Regular.ttf \
		$(TARGET_DIR)/usr/share/fonts/Roboto-Regular.ttf

	# Geist: gsmenu UI font, loaded at runtime from
	# /usr/share/pixelpilot/fonts (src/gsmenu/styles.c). Installed from the
	# fetched source tree so it always matches the built revision.
	$(INSTALL) -D -m 0644 $(@D)/src/gsmenu/fonts/Geist-Regular.ttf \
		$(TARGET_DIR)/usr/share/pixelpilot/fonts/Geist-Regular.ttf

endef

PIXELPILOT_POST_INSTALL_TARGET_HOOKS += PIXELPILOT_POST_INSTALL_TARGET_HOOK

$(eval $(cmake-package))
