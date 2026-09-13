#!/bin/sh
# autofs program map for /media (see /etc/auto.master), and the source of the
# USB mass-storage LUN in /usr/sbin/gadget.
#
# The DVR partition used to be hardcoded as p3. It is p4 now on any board that
# also carves a CONFIG partition (see the config block in board/common/overlay/init),
# and it would move again the next time a partition is added, so it is resolved
# by its GPT partition label instead. /init names it with `parted name <n> DVR`,
# which is exactly what /dev/disk/by-partlabel/ indexes.

key="$1"

# check if we are in gadget mode
[ -d /sys/kernel/config/usb_gadget/g1 ] && exit 1

ROOT_DEV=$(readlink -f /dev/disk/by-partlabel/rootfs)
DEV=""

# The DVR partition on whichever disk we booted from.
if [ -e /dev/disk/by-partlabel/DVR ]; then
    DEV=$(readlink -f /dev/disk/by-partlabel/DVR)
fi

# Booted from eMMC: an inserted SD card's first FAT partition wins over the
# on-board DVR partition, so recordings land on the removable media.
if [ "$ROOT_DEV" = "/dev/mmcblk0p1" ]; then
    if [ -b /dev/mmcblk1p1 ] && file -s /dev/mmcblk1p1 | grep -q 'FAT'; then
        DEV="/dev/mmcblk1p1"
    fi
fi

if [ -b "$DEV" ]; then
    echo "-fstype=vfat :$DEV"
else
    exit 1
fi
