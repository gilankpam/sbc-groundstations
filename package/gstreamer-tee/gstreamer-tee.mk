###############################################################################
#
# gstreamer-tee
#
###############################################################################

GSTREAMER_TEE_INSTALL_TARGET = YES

define GSTREAMER_TEE_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -D $(GSTREAMER_TEE_PKGDIR)/files/S99gstreamer-tee $(TARGET_DIR)/etc/init.d/S99gstreamer-tee
endef
$(eval $(generic-package))
