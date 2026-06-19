#!/usr/bin/env bash
# Regenerate board/orangepi/zero2w/patches/linux/ from kernel-patches.list.
# Needs an Armbian build tree (only to source the patch files) — NOT a build dependency.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ARMBIAN_BUILD="${ARMBIAN_BUILD:-$HOME/h618-kernel-work/armbian-build}"
SERIES_DIR="$ARMBIAN_BUILD/patch/kernel/archive/sunxi-6.18"
MISC_DIR="$ARMBIAN_BUILD/patch/misc/wireless-uwe5622"
USER_DIR="$ARMBIAN_BUILD/userpatches/kernel/archive/sunxi-6.18"
LOCAL_DIR="$REPO/board/orangepi/zero2w/patches-src"   # repo-owned patches (self-contained)
WT="$ARMBIAN_BUILD/cache/sources/linux-kernel-worktree/6.18__sunxi64__arm64"  # patched source (snapshot:)
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
		local)  src="$LOCAL_DIR/$ref" ;;
		snapshot)
			# Capture a fully-patched source tree from the Armbian worktree as ONE
			# add-files patch (source files only; build artifacts / .orig excluded).
			# More robust than replaying a fragile incremental upstream patch stack.
			[ -d "$WT/$ref" ] || { echo "ERROR: snapshot path not in worktree: $WT/$ref (set ARMBIAN_BUILD=)"; exit 1; }
			out="$OUT/${pfx}-snapshot-$(echo "$ref" | tr / -).patch"
			: > "$out"
			while IFS= read -r f; do
				LC_ALL=C diff -u /dev/null "$WT/$f" \
					| sed -e "1s|^--- .*|--- /dev/null|" -e "2s|^+++ .*|+++ b/$f|" >> "$out" || true
			done < <(cd "$WT" && find "$ref" -type f \
				! -name '*.o' ! -name '*.ko' ! -name '*.a' ! -name '*.cmd' ! -name '.*.cmd' \
				! -name '*.mod' ! -name '*.mod.c' ! -name '*.order' ! -name 'modules.order' \
				! -name '*.orig' ! -name '*.d' ! -name '.*.d' | LC_ALL=C sort)
			[ -s "$out" ] || { echo "ERROR: empty snapshot for $ref"; exit 1; }
			grep -q "^Binary files" "$out" && { echo "ERROR: binary file in snapshot $ref (refine filter)"; exit 1; }
			echo "  $pfx <- snapshot: $ref ($(grep -c '^+++ b/' "$out") files)"
			continue ;;
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
			if [ "$ref" = "uwe5622-wireless-kconfig" ]; then
				# Wire uwe5622 into drivers/net/wireless/Kconfig with pristine-6.18.35
				# context. The base patch's own Kconfig hunk assumes Armbian-added
				# rtl8189es/fs source lines (absent upstream) and is stripped on copy.
				cat > "$OUT/${pfx}-uwe5622-wireless-kconfig.patch" <<'PATCH'
--- a/drivers/net/wireless/Kconfig
+++ b/drivers/net/wireless/Kconfig
@@ -37,4 +37,5 @@
 source "drivers/net/wireless/zydas/Kconfig"
 source "drivers/net/wireless/quantenna/Kconfig"
+source "drivers/net/wireless/uwe5622/Kconfig"

 source "drivers/net/wireless/virtual/Kconfig"
PATCH
				echo "  $pfx <- gen: uwe5622-wireless-kconfig (synthesized)"
				continue
			fi
			echo "ERROR: unknown gen ref '$ref'"; exit 1 ;;
		*) echo "ERROR: bad manifest line: $line"; exit 1 ;;
	esac
	[ -f "$src" ] || { echo "ERROR: missing patch source: $src"; exit 1; }
	dst="$OUT/${pfx}-$(basename "$ref")"
	if [ "$kind" = "misc" ]; then
		# uwe5622 patches: drop hunks for files we deliberately do NOT carry:
		#  - the top-level drivers/net/wireless/Kconfig (context assumes Armbian
		#    rtl8189es/fs entries; we wire uwe5622 via gen: uwe5622-wireless-kconfig)
		#  - ALL Bluetooth core files (this board uses no BT; the sprd BT quirk hunks
		#    depend on the dropped park-link patch and would fail to apply/compile).
		# The uwe5622 driver's own tree (drivers/net/wireless/uwe5622/**, including its
		# tty-sdio BT glue and Kconfig) has different paths and is preserved.
		awk '
			/^diff --git a\/drivers\/net\/wireless\/Kconfig / { skip=1; next }
			/^diff --git a\/drivers\/bluetooth\// { skip=1; next }
			/^diff --git a\/net\/bluetooth\// { skip=1; next }
			/^diff --git a\/include\/net\/bluetooth\// { skip=1; next }
			skip && /^diff --git / { skip=0 }
			!skip { print }
		' "$src" > "$dst"
	else
		cp "$src" "$dst"
	fi
	echo "  $pfx <- $kind: $ref"
done < "$MANIFEST"

echo "OK: wrote $n patches to $OUT"
