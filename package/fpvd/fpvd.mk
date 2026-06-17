################################################################################
#
# fpvd
#
################################################################################

# feat/pixelpilot-managed-service HEAD (after the dynlink package-data fix).
# Bump this hash to advance the branch.
FPVD_VERSION = 7c900accc73819c48d78f916d6367bdd71f1f29f
FPVD_SITE = https://github.com/gilankpam/fpvd.git
FPVD_SITE_METHOD = git
FPVD_SUBDIR = gs
FPVD_SETUP_TYPE = pep517

# wfb-server provides the wfb_ng Python module fpvd imports; wifibroadcast-ng
# provides the wfb_rx/wfb_tx binaries + keys fpvd drives; pixelpilot provides the
# binary fpvd spawns. Depending on them also forces fpvd to install AFTER them,
# which the launcher-retirement step below relies on.
# host-python-setuptools/wheel supply the pep517 build backend (--no-isolation).
FPVD_DEPENDENCIES = \
	pixelpilot \
	wfb-server \
	wifibroadcast-ng \
	host-python-setuptools \
	host-python-wheel

define FPVD_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(@D)/gs/scripts/S99fpvd \
		$(TARGET_DIR)/etc/init.d/S99fpvd
endef

define FPVD_POST_INSTALL_TARGET_HOOK
	mkdir -p $(TARGET_DIR)/etc/fpvd

	$(INSTALL) -D -m 0644 $(FPVD_PKGDIR)/files/config.json \
		$(TARGET_DIR)/etc/fpvd/config.json

	# Full GS-supervisor handoff: fpvd runs the wfb data plane in-process
	# (wfb_ng) and supervises pixelpilot directly, so retire the stock
	# auto-start scaffolding of both. Kept: the wfb binaries/keys/cfg
	# (fpvd regenerates the cfg via --cfg-out) and the pixelpilot binary +
	# fonts. Removed: only the launchers. Reverts automatically when
	# BR2_PACKAGE_FPVD is disabled (each package still ships its own launcher).
	rm -f $(TARGET_DIR)/etc/init.d/S98wifibroadcast
	rm -f $(TARGET_DIR)/etc/init.d/S99pixelpilot \
	      $(TARGET_DIR)/usr/bin/pixelpilot.sh \
	      $(TARGET_DIR)/etc/default/pixelpilot
endef

FPVD_POST_INSTALL_TARGET_HOOKS += FPVD_POST_INSTALL_TARGET_HOOK

$(eval $(python-package))
