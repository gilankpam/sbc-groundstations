################################################################################
#
# wfb_server
#
################################################################################

WFB_SERVER_VERSION = fe9ca01b6fa6bd7eb3a8740eb234cff2eca3b48e
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
    COMMIT=fe9ca01b6fa6bd7eb3a8740eb234cff2eca3b48e \
    OMIT_DATA_FILES=True

$(eval $(python-package))
