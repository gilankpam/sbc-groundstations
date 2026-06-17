################################################################################
#
# wfb_server
#
################################################################################

WFB_SERVER_VERSION = 77d60021950e9572a7675faaac220889d6d18c3f
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
    COMMIT=77d60021950e9572a7675faaac220889d6d18c3f \
    OMIT_DATA_FILES=True

$(eval $(python-package))
