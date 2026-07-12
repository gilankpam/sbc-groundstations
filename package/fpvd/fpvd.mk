################################################################################
#
# fpvd
#
################################################################################

# feat/pixelpilot-managed-service HEAD (after the dynlink package-data fix).
# Bump this hash to advance the branch.
FPVD_VERSION = 98c73b7dc0bd73bdc1f2d067a9569746bbd6beae
FPVD_SITE = https://github.com/gilankpam/fpvd.git
FPVD_SITE_METHOD = git
FPVD_SUBDIR = gs
FPVD_SETUP_TYPE = pep517

# wifibroadcast-ng provides the wfb_rx/wfb_tx binaries + keys fpvd drives
# (native orchestration spawns them directly; the retired wfb_ng Python module
# / wfb-server is no longer needed). Depending on it also forces fpvd to install
# AFTER it, which the launcher-retirement step below relies on.
# host-python-setuptools/wheel supply the pep517 build backend (--no-isolation).
FPVD_DEPENDENCIES = \
	wifibroadcast-ng \
	host-python-setuptools \
	host-python-wheel

# pixelpilot is fpvd's display process only on boards that build it (Rockchip).
# Boards that drive the display another way (e.g. orangepi/citruspilot) leave
# pixelpilot disabled; fpvd then supervises no display and the board's own
# player launcher stays in charge. Only depend on pixelpilot when it is built,
# so enabling fpvd does not drag the Rockchip-only pixelpilot into the build.
ifeq ($(BR2_PACKAGE_PIXELPILOT),y)
FPVD_DEPENDENCIES += pixelpilot
endif

define FPVD_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(@D)/gs/scripts/S99fpvd \
		$(TARGET_DIR)/etc/init.d/S99fpvd
endef

# When pixelpilot is not built, fpvd must not try to spawn it: flip its display
# supervision off in the installed config so fpvd runs link-only and leaves the
# screen to the board's own player launcher (e.g. citruspilot on orangepi).
# Scoped to the pixelpilot block so the other *.enabled flags are untouched.
ifneq ($(BR2_PACKAGE_PIXELPILOT),y)
define FPVD_DISABLE_PIXELPILOT_SUPERVISION
	$(SED) '/"pixelpilot": {/,/"bin":/ s/"enabled": true/"enabled": false/' \
		$(TARGET_DIR)/etc/fpvd/config.json
endef
else
# pixelpilot IS built: fpvd supervises it directly, so retire pixelpilot's own
# auto-start launcher (fpvd owns its lifecycle). The binary + fonts are kept.
define FPVD_RETIRE_PIXELPILOT_LAUNCHER
	rm -f $(TARGET_DIR)/etc/init.d/S99pixelpilot \
	      $(TARGET_DIR)/usr/bin/pixelpilot.sh \
	      $(TARGET_DIR)/etc/default/pixelpilot
endef
endif

define FPVD_POST_INSTALL_TARGET_HOOK
	mkdir -p $(TARGET_DIR)/etc/fpvd

	$(INSTALL) -D -m 0644 $(FPVD_PKGDIR)/files/config.json \
		$(TARGET_DIR)/etc/fpvd/config.json

	# fpvd runs the wfb data plane in-process (wfb_ng), so always retire the
	# stock wfb launcher. Kept: the wfb binaries/keys/cfg (fpvd regenerates the
	# cfg via --cfg-out). Reverts automatically when BR2_PACKAGE_FPVD is
	# disabled (wifibroadcast-ng still ships its own launcher).
	rm -f $(TARGET_DIR)/etc/init.d/S98wifibroadcast

	$(FPVD_RETIRE_PIXELPILOT_LAUNCHER)
	$(FPVD_DISABLE_PIXELPILOT_SUPERVISION)
endef

FPVD_POST_INSTALL_TARGET_HOOKS += FPVD_POST_INSTALL_TARGET_HOOK

$(eval $(python-package))
