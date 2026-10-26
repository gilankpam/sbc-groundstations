# Sourced by /init. Tested on the host by tests/carve-part.test.sh.

# part_nums: the partition numbers on $BOOT_DISK, one per line.
part_nums() {
  parted -sm $BOOT_DISK print 2>/dev/null | awk -F: '/^[0-9]+:/ {print $1}'
}

# carve_part <name> <mkpart args...>: create a partition on $BOOT_DISK, give
# it the GPT name <name>, and print its number for the caller to format.
#
# Fails, printing nothing and touching nothing, unless mkpart succeeded AND
# exactly one partition number appeared that was not there before. Taking
# "the last partition" instead is what used to format the wrong one: on a disk
# laid out by an image without a CONFIG partition, DVR already fills the disk,
# mkpart fails, and the last partition IS the DVR -- renamed and mkfs'd on
# every boot, recordings and all. A sysupgrade keeps the old partition table,
# so such disks are the normal case after an upgrade, not a corner.
carve_part() {
  name=$1
  shift
  before=$(part_nums)
  if ! parted --fix -s $BOOT_DISK mkpart "$@"; then
    echo "carve: mkpart $* on $BOOT_DISK failed -- no $name partition" >&2
    return 1
  fi
  partprobe $BOOT_DISK
  new=$(part_nums | awk -v before=" $(echo $before) " 'index(before, " " $1 " ") == 0')
  case "$new" in
    ''|*[!0-9]*)
      echo "carve: no single new partition after mkpart $* on $BOOT_DISK (got '$new') -- no $name partition" >&2
      return 1
      ;;
  esac
  parted -s $BOOT_DISK name $new $name || return 1
  echo $new
}
