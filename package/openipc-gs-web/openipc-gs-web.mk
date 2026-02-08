################################################################################
#
# openipc-gs-web
#
################################################################################

OPENIPC_GS_WEB_VERSION = main
OPENIPC_GS_WEB_SITE = https://github.com/gilankpam/openipc-gs-web
OPENIPC_GS_WEB_SITE_METHOD = git
OPENIPC_GS_WEB_LICENSE = MIT
OPENIPC_GS_WEB_LICENSE_FILES = LICENSE

OPENIPC_GS_WEB_DEPENDENCIES = host-go host-nodejs

OPENIPC_GS_WEB_GOMOD = ./

# Build the gs-server binary
OPENIPC_GS_WEB_BUILD_TARGETS = cmd/gs-server

# Build the frontend (React)
define OPENIPC_GS_WEB_BUILD_FRONTEND
	cd $(@D)/web && npm install && npm run build
endef


define OPENIPC_GS_WEB_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/bin/gs-server $(TARGET_DIR)/usr/bin/gs-server
endef

OPENIPC_GS_WEB_PRE_BUILD_HOOKS += OPENIPC_GS_WEB_BUILD_FRONTEND

define OPENIPC_GS_WEB_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/package/openipc-gs-web/files/S99openipc-gs-web \
		$(TARGET_DIR)/etc/init.d/S99openipc-gs-web
endef

define OPENIPC_GS_WEB_INSTALL_STATIC_FILES
	mkdir -p $(TARGET_DIR)/var/www/openipc-gs-web
	cp -r $(@D)/web/dist/* $(TARGET_DIR)/var/www/openipc-gs-web/
endef
OPENIPC_GS_WEB_POST_INSTALL_TARGET_HOOKS += OPENIPC_GS_WEB_INSTALL_STATIC_FILES

$(eval $(golang-package))
