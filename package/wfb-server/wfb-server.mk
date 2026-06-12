################################################################################
#
# wfb_server
#
################################################################################

WFB_SERVER_VERSION = 4964237d710509884b15c47adebc56a486c97720
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
    COMMIT=4964237d710509884b15c47adebc56a486c97720 \
    OMIT_DATA_FILES=True

$(eval $(python-package))
