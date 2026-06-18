#!/usr/bin/env bash
# Regenerate the large, gitignored kernel build input for the Orange Pi Zero 2W
# (H618) board into .opi-artifacts/, referenced by
#   configs/orangepi_zero2w_defconfig   (BR2_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION)
# Run this once before building this board.
#
#   1. linux-6.18.35-opi-sunxi.tar.gz  - clean source snapshot of the Armbian-
#      patched 6.18.35 sunxi kernel (mainline + DE33 + the 0099/0100 video
#      userpatches + uwe5622 driver + the HDMI/WiFi board DTS).
#
# (ffmpeg is now the standalone package/ffmpeg-v4l2request, downloaded by
# Buildroot, so it is no longer prepared here.)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ART="$REPO/.opi-artifacts"
mkdir -p "$ART"

# Point ARMBIAN_BUILD at your Armbian build tree whose kernel worktree holds
# mainline 6.18.35 + Armbian patches + the 0099/0100 video userpatches applied.
ARMBIAN_BUILD="${ARMBIAN_BUILD:-$HOME/h618-kernel-work/armbian-build}"
WT="$ARMBIAN_BUILD/cache/sources/linux-kernel-worktree/6.18__sunxi64__arm64"
BARE="$ARMBIAN_BUILD/cache/git-bare/kernel/.git/objects"

# --- 1. kernel source snapshot ---------------------------------------------
TARBALL="$ART/linux-6.18.35-opi-sunxi.tar.gz"
if [ -f "$TARBALL" ]; then
	echo "kernel snapshot exists: $TARBALL (delete to regenerate)"
else
	[ -d "$WT" ] || { echo "ERROR: Armbian kernel worktree not found: $WT (set ARMBIAN_BUILD=)"; exit 1; }
	echo "Snapshotting Armbian-patched kernel source -> $TARBALL ..."
	# Clean source (no build artifacts, via the kernel .gitignore) using a temp
	# git index + a writable object dir, without disturbing the Armbian tree.
	export GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_INDEX_FILE
	GIT_OBJECT_DIRECTORY="$(mktemp -d)"
	GIT_ALTERNATE_OBJECT_DIRECTORIES="$BARE"
	GIT_INDEX_FILE="$(mktemp -u)"
	SD="-c safe.directory=$WT"
	git $SD -C "$WT" read-tree HEAD
	git $SD -C "$WT" add -A
	TREE="$(git $SD -C "$WT" write-tree)"
	COMMIT="$(printf 'opi-zero2w armbian 6.18.35 snapshot\n' | git $SD -C "$WT" commit-tree "$TREE" -p HEAD)"
	git $SD -C "$WT" archive --format=tar --prefix=linux-6.18.35-opi-sunxi/ "$COMMIT" | gzip -1 > "$TARBALL"
	echo "  done: $(du -h "$TARBALL" | cut -f1)"
fi

echo "OK: artifacts ready in $ART"
