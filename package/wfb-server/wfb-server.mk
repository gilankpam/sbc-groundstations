################################################################################
#
# wfb_server
#
################################################################################

WFB_SERVER_VERSION = e8033cf9cf5a2081447ae45bf441bc68c28a26da
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
    COMMIT=e8033cf9cf5a2081447ae45bf441bc68c28a26da \
    OMIT_DATA_FILES=True

$(eval $(python-package))
