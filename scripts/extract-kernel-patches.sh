#!/usr/bin/env bash
# Regenerate board/orangepi/zero2w/patches/linux/ from kernel-patches.list.
# Needs an Armbian build tree (only to source the patch files) — NOT a build dependency.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ARMBIAN_BUILD="${ARMBIAN_BUILD:-$HOME/h618-kernel-work/armbian-build}"
SERIES_DIR="$ARMBIAN_BUILD/patch/kernel/archive/sunxi-6.18"
MISC_DIR="$ARMBIAN_BUILD/patch/misc/wireless-uwe5622"
USER_DIR="$ARMBIAN_BUILD/userpatches/kernel/archive/sunxi-6.18"
MANIFEST="$REPO/board/orangepi/zero2w/kernel-patches.list"
OUT="$REPO/board/orangepi/zero2w/patches/linux"

[ -d "$SERIES_DIR" ] || { echo "ERROR: Armbian tree not found at $ARMBIAN_BUILD (set ARMBIAN_BUILD=)"; exit 1; }
rm -rf "$OUT"; mkdir -p "$OUT"

n=0
while IFS= read -r line; do
	line="${line%%#*}"; line="$(echo "$line" | xargs || true)"   # strip comment + trim
	[ -z "$line" ] && continue
	kind="${line%%:*}"; ref="$(echo "${line#*:}" | xargs)"
	n=$((n+1)); pfx="$(printf '%04d' "$n")"
	case "$kind" in
		series) src="$SERIES_DIR/$ref" ;;
		misc)   src="$MISC_DIR/$ref" ;;
		user)   src="$USER_DIR/$ref" ;;
		gen)
			if [ "$ref" = "uwe5622-wireless-makefile" ]; then
				# Append ONLY the uwe5622 subdir to drivers/net/wireless/Makefile.
				# Synthesized inline (NOT diffed from the Armbian worktree, whose
				# Makefile also carries other out-of-tree drivers' harness appends),
				# so the output is deterministic and scoped to uwe5622 alone.
				cat > "$OUT/${pfx}-uwe5622-wireless-makefile.patch" <<'PATCH'
--- a/drivers/net/wireless/Makefile
+++ b/drivers/net/wireless/Makefile
@@ -23,3 +23,4 @@ obj-$(CONFIG_WLAN_VENDOR_TI) += ti/
 obj-$(CONFIG_WLAN_VENDOR_ZYDAS) += zydas/

 obj-$(CONFIG_WLAN) += virtual/
+obj-$(CONFIG_SPARD_WLAN_SUPPORT) += uwe5622/
PATCH
				echo "  $pfx <- gen: uwe5622-wireless-makefile (synthesized)"
				continue
			fi
			echo "ERROR: unknown gen ref '$ref'"; exit 1 ;;
		*) echo "ERROR: bad manifest line: $line"; exit 1 ;;
	esac
	[ -f "$src" ] || { echo "ERROR: missing patch source: $src"; exit 1; }
	cp "$src" "$OUT/${pfx}-$(basename "$ref")"
	echo "  $pfx <- $kind: $ref"
done < "$MANIFEST"

echo "OK: wrote $n patches to $OUT"
