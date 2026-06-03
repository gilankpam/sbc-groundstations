################################################################################
#
# fpvd
#
################################################################################

# feat/pixelpilot-managed-service HEAD (after the dynlink package-data fix).
# Bump this hash to advance the branch.
FPVD_VERSION = 94d06c160bff73a133ad5824415bffb242c18e3a
FPVD_SITE = https://github.com/gilankpam/fpvd.git
FPVD_SITE_METHOD = git
FPVD_SUBDIR = gs
FPVD_SETUP_TYPE = pep517

# wfb-server provides the wfb_ng Python module fpvd imports; wifibroadcast-ng
# provides the wfb_rx/wfb_tx binaries + keys fpvd drives. Depending on them also
# forces fpvd to install AFTER wifibroadcast-ng, which the S98 removal relies on.
# host-python-setuptools/wheel supply the pep517 build backend (--no-isolation).
FPVD_DEPENDENCIES = \
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

	$(INSTALL) -D -m 0644 $(@D)/gs/etc/defaults.json \
		$(TARGET_DIR)/etc/fpvd/defaults.json

	$(INSTALL) -D -m 0644 $(@D)/deploy/gs/config.json \
		$(TARGET_DIR)/etc/fpvd/config.json

	# Full GS-supervisor handoff: fpvd runs the wfb data plane in-process
	# (wfb_ng), so retire wifibroadcast-ng's stock launcher. The wfb binaries,
	# keys, and /etc/wifibroadcast.cfg from wifibroadcast-ng stay -- fpvd
	# regenerates the cfg at runtime via its --cfg-out. Reverts automatically
	# when BR2_PACKAGE_FPVD is disabled.
	rm -f $(TARGET_DIR)/etc/init.d/S98wifibroadcast
endef

FPVD_POST_INSTALL_TARGET_HOOKS += FPVD_POST_INSTALL_TARGET_HOOK

$(eval $(python-package))
