################################################################################
#
# citruspilot
#
# Low-latency FPV H.265 player for the Orange Pi Zero 2W (Allwinner H618):
# libav RTP front-end -> Cedrus HW decode -> direct-to-plane scanout on the
# DE33 display engine. The sunxi analog of pixelpilot (which targets Rockchip).
#
# Plain Makefile build (no autotools/cmake); mirror the documented cross-build:
# point CC at the target toolchain and SYSROOT at the staging tree so the
# libav* (from ffmpeg-v4l2request) and libdrm headers/libs are found.
#
################################################################################

CITRUSPILOT_VERSION = f7ddede3d95d0eeb6d4e5fc2ccef33b7d254c619
CITRUSPILOT_SITE = https://github.com/gilankpam/citruspilot.git
CITRUSPILOT_SITE_METHOD = git
CITRUSPILOT_INSTALL_STAGING = NO
CITRUSPILOT_INSTALL_TARGET = YES
CITRUSPILOT_DEPENDENCIES = ffmpeg-v4l2request libdrm

define CITRUSPILOT_BUILD_CMDS
	$(MAKE) -C $(@D) CC="$(TARGET_CC)" SYSROOT=$(STAGING_DIR) CFLAGS="$(TARGET_CFLAGS)"
endef

define CITRUSPILOT_INSTALL_TARGET_CMDS
	$(MAKE) -C $(@D) install PREFIX=/usr DESTDIR=$(TARGET_DIR)
endef

# Launch chain (init script + respawn wrapper), modeled on pixelpilot.
# citruspilot is player-only: it listens forever on udp:5600, where this
# board's wfb gs_video already forwards the de-FEC'd RTP.
define CITRUSPILOT_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(CITRUSPILOT_PKGDIR)/files/S99citruspilot \
		$(TARGET_DIR)/etc/init.d/S99citruspilot

	$(INSTALL) -D -m 0755 $(CITRUSPILOT_PKGDIR)/files/citruspilot.sh \
		$(TARGET_DIR)/usr/bin/citruspilot.sh
endef

define CITRUSPILOT_POST_INSTALL_TARGET_HOOK
	# Env/args for the launch chain (sourced by citruspilot.sh).
	$(INSTALL) -D -m 0644 $(CITRUSPILOT_PKGDIR)/files/citruspilot \
		$(TARGET_DIR)/etc/default/citruspilot
endef

CITRUSPILOT_POST_INSTALL_TARGET_HOOKS += CITRUSPILOT_POST_INSTALL_TARGET_HOOK

$(eval $(generic-package))
