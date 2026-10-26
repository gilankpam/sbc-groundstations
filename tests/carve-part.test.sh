#!/bin/sh
# Host-side tests for board/common/overlay/usr/lib/carve-part.sh, the
# partition-carving helper /init uses for overlayfs, CONFIG and DVR.
#
#   sh tests/carve-part.test.sh
#
# Runs the real parted against disk-image files, so it needs parted on PATH
# (e.g. `nix-shell -p parted --run "sh tests/carve-part.test.sh"`).

cd "$(dirname "$0")/.." || exit 1
LIB=$PWD/board/common/overlay/usr/lib/carve-part.sh

command -v parted >/dev/null || { echo "SKIP: parted not on PATH"; exit 0; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

pass=0
fail=0
name=

ok() { pass=$((pass + 1)); }
ko() { fail=$((fail + 1)); echo "FAIL [$name] $*"; }

# names <disk>: "num:name" per partition, space-separated.
names() {
	parted -sm "$1" print | awk -F: '/^[0-9]+:/ {printf "%s%s:%s", sep, $1, $6; sep=" "}'
}
expect_names() {
	got=$(names "$1")
	[ "$got" = "$2" ] && ok || ko "partitions: want '$2', got '$got'"
}

# carve <disk> <name> <mkpart args...>: run carve_part in a subshell the way
# /init does, with BOOT_DISK set; stdout to $T/out, status to $rc.
carve() {
	disk=$1
	shift
	(BOOT_DISK=$disk; . "$LIB"; carve_part "$@") >"$T/out" 2>"$T/err"
	rc=$?
}

# ── Room left: the new partition is created, named, and its number printed ──
name=fresh
D=$T/fresh.img
truncate -s 1G "$D"
parted -s "$D" mklabel gpt
parted -s "$D" mkpart rootfs 16MiB 200MiB
carve "$D" CONFIG primary fat32 220MiB 284MiB
[ "$rc" = 0 ] && ok || ko "rc=$rc, want 0 (stderr: $(cat "$T/err"))"
[ "$(cat "$T/out")" = 2 ] && ok || ko "printed '$(cat "$T/out")', want 2"
expect_names "$D" "1:rootfs 2:CONFIG"

# ── No room: an older image's DVR already fills the disk. ───────────────────
# mkpart fails; the last existing partition (DVR) must be left untouched --
# not renamed, and no number printed for the caller to mkfs.
name=full-disk
D=$T/full.img
truncate -s 1G "$D"
parted -s "$D" mklabel gpt
parted -s "$D" mkpart rootfs 16MiB 200MiB
parted -s "$D" mkpart overlayfs 220MiB 400MiB
parted -s "$D" mkpart DVR 420MiB 100%
carve "$D" CONFIG primary fat32 1100MiB 1164MiB
[ "$rc" != 0 ] && ok || ko "rc=0, want failure"
[ -s "$T/out" ] && ko "printed '$(cat "$T/out")', want nothing" || ok
expect_names "$D" "1:rootfs 2:overlayfs 3:DVR"

# Same disk, the DVR carve /init would try next ("<last end>+21MB" to 100%).
name=full-disk-dvr
carve "$D" DVR primary fat32 1100MB 100%
[ "$rc" != 0 ] && ok || ko "rc=0, want failure"
[ -s "$T/out" ] && ko "printed '$(cat "$T/out")', want nothing" || ok
expect_names "$D" "1:rootfs 2:overlayfs 3:DVR"

echo "carve-part: $pass passed, $fail failed"
[ "$fail" = 0 ]
