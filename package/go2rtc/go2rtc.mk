###############################################################################
#
# GO2RTC
#
###############################################################################

GO2RTC_VERSION = v1.9.13
GO2RTC_SOURCE = go2rtc_linux_arm64
GO2RTC_SITE = https://github.com/AlexxIT/go2rtc/releases/download/$(GO2RTC_VERSION)
GO2RTC_SITE_METHOD = wget
GO2RTC_INSTALL_TARGET = YES

GO2RTC_EXTRACT_CMDS =

define GO2RTC_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 $(@D)/go2rtc_linux_arm64 $(TARGET_DIR)/usr/bin/go2rtc
	$(INSTALL) -m 755 -D $(GO2RTC_PKGDIR)/files/S99go2rtc $(TARGET_DIR)/etc/init.d/S99go2rtc
endef
$(eval $(generic-package))
