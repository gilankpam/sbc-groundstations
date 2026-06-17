# Orange Pi Zero 2W package overrides. Includes the common overrides, then adds
# the board-specific ffmpeg source override.
include $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/board/common/local.mk

# Build ffmpeg from jernejsk/FFmpeg @ v4l2-request-n7.1 (7.1 + V4L2-Request
# hwaccel) instead of Buildroot's stock 6.1.3. override-srcdir also bypasses
# Buildroot's 6.1.3-specific ffmpeg patches, which do not apply to 7.1.
# NOTE: absolute local path (operator's build machine); pin/relocate for CI.
FFMPEG_OVERRIDE_SRCDIR = /home/gilankpam/h618-kernel-work/ffmpeg-v4l2request-n7.1
