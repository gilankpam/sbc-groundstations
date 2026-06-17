# Orange Pi Zero 2W package overrides (BR2_PACKAGE_OVERRIDE_FILE).
#
# Build ffmpeg from jernejsk/FFmpeg @ v4l2-request-n7.1 (7.1 + V4L2-Request
# hwaccel) instead of Buildroot's stock 6.1.3. override-srcdir also bypasses
# Buildroot's 6.1.3-specific ffmpeg patches, which do not apply to 7.1.
# NOTE: absolute local path (operator's build machine); pin/relocate for CI.
#
# (The common board/common/local.mk only carries CI=true cleanup hooks, which
# are irrelevant to a local build, so it is intentionally not included here.)
FFMPEG_OVERRIDE_SRCDIR = $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/.opi-artifacts/ffmpeg-v4l2request-n7.1
