################################################################################
#
# rockchip-mpp
#
################################################################################

# Pinned to the commit mabur builds its static MPP from (MPP_REF in
# mabur's tools/build-arm64.sh), so the image's shared librockchip_mpp and
# mabur's dev build are one decoder. The 000N-*.patch files beside this file
# (fpvOS rkvdec2 stream mode, ported to this commit) are COPIES: the
# canonical ones live in mabur, gs/player/mpp-patches/. Change them there,
# then copy them here byte for byte.
ROCKCHIP_MPP_VERSION = 14729dd578e570e5f00fd1dd2113f5429012d64b
ROCKCHIP_MPP_SITE = https://github.com/rockchip-linux/mpp.git
ROCKCHIP_MPP_SITE_METHOD = git
ROCKCHIP_MPP_INSTALL_STAGING = YES
ROCKCHIP_MPP_INSTALL_TARGET = YES

# BUILD_TEST=ON: the stream-mode bench runs mpi_dec_stream_test (added by
# 0001) on the GS. Size cost accepted.
ROCKCHIP_MPP_CONF_OPTS = \
	-DRKPLAT=ON \
	-DHAVE_DRM=ON \
	-DBUILD_TEST=ON

$(eval $(cmake-package))
