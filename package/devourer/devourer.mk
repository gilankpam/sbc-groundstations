################################################################################
#
# devourer
#
################################################################################

# gilankpam/devourer master, resolved to a hash on every make invocation -- see
# the note in package/mabur/mabur.mk, which tracks its master the same way.
# Override with `make DEVOURER_VERSION=<sha-or-tag> mabur-rebuild`.
DEVOURER_MASTER_SHA := $(shell GIT_TERMINAL_PROMPT=0 timeout 15 \
	git ls-remote https://github.com/gilankpam/devourer.git \
	refs/heads/master 2>/dev/null | cut -f1)
DEVOURER_VERSION = $(or $(DEVOURER_MASTER_SHA),3b15c7ae8dc0fe3608ed42a95750a1b4eb605704)
DEVOURER_SITE = https://github.com/gilankpam/devourer.git
DEVOURER_SITE_METHOD = git
DEVOURER_LICENSE = GPL-2.0
DEVOURER_INSTALL_STAGING = NO
DEVOURER_INSTALL_TARGET = NO

# Nothing is compiled here. mabur's top-level CMakeLists.txt pulls devourer in
# with add_subdirectory(${DEVOURER_DIR} ... EXCLUDE_FROM_ALL), so what mabur
# needs is the *source tree on disk* at its own configure time. This package
# exists to make Buildroot fetch and extract it -- and to define DEVOURER_DIR,
# which the package infrastructure sets to $(BUILD_DIR)/devourer-$(VERSION),
# exactly the cache variable mabur's CMake expects. See package/mabur/mabur.mk.
#
# libusb is still a dependency: devourer's CMake does
# pkg_check_modules(libusb REQUIRED IMPORTED_TARGET libusb-1.0), and that runs
# during *mabur's* configure step, so libusb has to be staged by then.
DEVOURER_DEPENDENCIES = libusb

DEVOURER_CONFIGURE_CMDS =
DEVOURER_BUILD_CMDS =
DEVOURER_INSTALL_TARGET_CMDS =

$(eval $(generic-package))
