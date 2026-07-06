################################################################################
#
# wfb_server
#
################################################################################

WFB_SERVER_VERSION = 2631e0d26fe070341cc945c3d12c85d24ed2e007
WFB_SERVER_SITE = https://github.com/gilankpam/wfb-ng.git
WFB_SERVER_SITE_METHOD = git
WFB_SERVER_LICENSE = GPL-3.0
WFB_SERVER_SETUP_TYPE = setuptools

WFB_SERVER_PYTHON_DEPENDENCIES = \
    python \
    libpcap \
    libsodium \
    libevent

WFB_SERVER_BUILD_ENV = \
    VERSION=25.5.1 \
    COMMIT=2631e0d26fe070341cc945c3d12c85d24ed2e007 \
    OMIT_DATA_FILES=True

$(eval $(python-package))
