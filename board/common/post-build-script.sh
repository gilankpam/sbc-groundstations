#!/usr/bin/bash

eval $(grep BR2_DEFCONFIG ${O}/.config)
echo "BUILD_CONFIG=$(basename $(basename $BR2_DEFCONFIG) _defconfig)" >> $TARGET_DIR/etc/os-release

DOWNLOAD_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-OpenIPC/sbc-groundstations}/releases/download/buildroot-snapshot/$(basename $(basename $BR2_DEFCONFIG) _defconfig).tar.gz"
# Get version: tag or short SHA, add -dirty if repo is dirty
if git describe --tags --exact-match >/dev/null 2>&1; then
    # Building from a tag
    VERSION=$(git describe --tags)
else
    # Not a tag, use short SHA
    VERSION=$(git rev-parse --short HEAD)
fi

# Check if repo is dirty (has uncommitted changes)
if ! git diff --quiet || ! git diff --cached --quiet; then
    VERSION="${VERSION}-dirty"
fi

cat <<EOF >$TARGET_DIR/etc/os-release
PRETTY_NAME="OpenIPC SBC GS"
NAME="OpenIPC SBC GS"
HOME_URL="https://github.com/OpenIPC/sbc-groundstations"
SUPPORT_URL="https://t.me/+BMyMoolVOpkzNWUy"
BUG_REPORT_URL="https://github.com/OpenIPC/sbc-groundstations/issues"
BUILD_CONFIG=$(basename $(basename $BR2_DEFCONFIG) _defconfig)
UPGRADE=$DOWNLOAD_URL
BUILD_DATE="$(date)"
VERSION="$VERSION"
EOF

cp ${O}/.config $TARGET_DIR/etc/default/br-config

AUTOMOUNT_INSERT_LINE=$(grep -n "# now run any rc scripts" $TARGET_DIR/etc/inittab| cut -d: -f1)
grep -q automount $TARGET_DIR/etc/inittab || sed -i "${AUTOMOUNT_INSERT_LINE}i # Start automount daemon\n::sysinit:/usr/sbin/automount\n" $TARGET_DIR/etc/inittab

grep -q gadget $TARGET_DIR/etc/inittab || echo '
# Start gadget
::sysinit:/usr/sbin/gadget init' >> $TARGET_DIR/etc/inittab

grep -q "Run customize.sh if it exists" $TARGET_DIR/etc/inittab || echo -e '
# Run customize.sh if it exists
::sysinit:/bin/sh -c '\''[ -f /media/dvr/customize.sh ] && /bin/sh /media/dvr/customize.sh'\''' >> $TARGET_DIR/etc/inittab

grep -q "framebuffer getty" $TARGET_DIR/etc/inittab || echo '
# framebuffer getty
tty1::askfirst:/sbin/getty -L tty1 0 vt100' >> $TARGET_DIR/etc/inittab

# Per-board edits to mabur's shipped defaults.
#
# /usr/share/config-defaults/maburplay.toml is mabur's own
# maburplay.default.toml, installed verbatim by package/mabur, and package/mabur
# tracks upstream master -- so the file gains keys on its own. The boards used to
# override it with a whole forked copy under
# board/*/overlay/usr/share/config-defaults/, which went stale the moment
# upstream added anything: that is how [colortrans] = true shipped disabled on
# every image after the GPU colortrans stage landed. Patch only the lines that
# actually differ, here, and everything else upstream ships stays current.
#
# This runs after both package install and the rootfs overlays (see
# target-finalize in buildroot/Makefile), so it is the last word on the file.
# The greps are load-bearing: if upstream renames or drops a block the sed
# silently becomes a no-op, so fail the build instead of shipping the default.
MABURPLAY_DEFAULTS=$TARGET_DIR/usr/share/config-defaults/maburplay.toml
BOARD=$(basename $(basename $BR2_DEFCONFIG) _defconfig)

case "$BOARD" in
emax_wyvern-link)
	# Strip [input.rec]. Upstream puts the DVR record button on header pin 32,
	# but this board's defconfig sets BR2_FACTORY_RESET_GPIO_PIN_NAME="PIN_32"
	# -- holding that pin during boot wipes the overlay. The block's presence is
	# the whole knob (there is no enable key), so removing it is what disables
	# the button; with dvr.autostart false this board never records. Give it a
	# pin that is actually free on the Wyvern-Link and delete this case to get
	# the button back.
	if ! grep -q '^\[input\.rec\]' $MABURPLAY_DEFAULTS; then
		echo "post-build: no [input.rec] in $MABURPLAY_DEFAULTS -- did mabur drop it?" >&2
		exit 1
	fi
	# Delete the block's keys (everything from the header to the next section
	# that is not itself a section header), then comment out the empty header.
	# In this order: an [input.rec] with no keys still reads as "button on,
	# defaults" to maburplay.
	sed -i '/^\[input\.rec\]/,/^\[/{/^\[/!d}' $MABURPLAY_DEFAULTS
	sed -i 's|^\[input\.rec\]$|# [input.rec] removed by board/common/post-build-script.sh: header pin\n# 32 is the factory-reset GPIO on this board.\n|' $MABURPLAY_DEFAULTS
	if grep -q '^\[input\.rec\]' $MABURPLAY_DEFAULTS; then
		echo "post-build: failed to strip [input.rec] from $MABURPLAY_DEFAULTS" >&2
		exit 1
	fi
	;;
esac
