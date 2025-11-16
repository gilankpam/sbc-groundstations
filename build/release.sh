#!/bin/bash

set -e

# Configuration
DISK_ADD_SIZE_GB=10
COMMIT_SHA="${1}"
GIT_REF="${2}"

# Color definitions
echo_red() { printf "\033[1;31m$*\033[m\n"; }
echo_green() { printf "\033[1;32m$*\033[m\n"; }
echo_blue() { printf "\033[1;34m$*\033[m\n"; }

# Globals
BUILD_DIR=$(dirname "$(readlink -f "$0")")
ROOTFS="rootfs"
IMAGE=""
LOOPDEV=""
ROOT_DEV=""

# Source config file
if [ -f "config" ]; then
    source config
else
    echo_red "Error: config file not found."
    exit 1
fi

#
# Prepares the image for the build
#
get_image() {
    echo_blue "Getting image..."
    cd "$BUILD_DIR"

    local found_image
    found_image=$(ls | grep "$(basename "$IMAGE_URL" "${IMAGE_URL: -3}")" | grep .img$ || true)

    if [ -f "$found_image" ]; then
        echo "Warning: Image '$found_image' file already exists, using it."
        IMAGE=$found_image
        return
    fi

    local image_archive
    if [[ "$IMAGE_URL" == http* ]]; then
        local basename
        basename=$(basename "$IMAGE_URL")
        if [ -f "$basename" ]; then
            echo "Warning: Archive file '$basename' already exists, using it."
        else
            wget -q --show-progress --progress=bar:force:noscroll "$IMAGE_URL"
        fi
        image_archive=$basename
    elif [[ "$IMAGE_URL" == *.img ]]; then
        cp "$IMAGE_URL" .
        IMAGE=$(basename "$IMAGE_URL")
        return
    else
        image_archive=$IMAGE_URL
    fi

    if [ -n "$image_archive" ]; then
        if file "$image_archive" | grep -q "XZ compressed"; then
            unxz -vf -T0 "${image_archive}"
        elif file "$image_archive" | grep -q "7-zip archive data"; then
            7z x "${image_archive}" -y -sdel
        else
            echo_red "Exception: Unknown archive type '${image_archive}'"
            exit 1
        fi
        rm -f *.sha
        found_image=$(ls | grep "$(basename "$image_archive" "${image_archive: -3}")" | grep .img$ || true)
        if [ "$(echo "$found_image" | wc -l)" -gt 1 ]; then
            echo_red "Exception: There are more than one file matching '$image_archive'"
            echo "$found_image"
            exit 1
        fi
        IMAGE=$found_image
    fi

    if [ ! -f "$IMAGE" ]; then
        echo_red "Image '$IMAGE' not found"
        exit 1
    fi
}

#
# Expands and mounts the image
#
expand_and_mount_image() {
    echo_blue "Expanding and mounting image..."
    cd "$BUILD_DIR"

    truncate -s +"${DISK_ADD_SIZE_GB}G" "$IMAGE"
    LOOPDEV=$(losetup -P --show -f "$IMAGE")
    ROOT_DEV=${LOOPDEV}p${ROOT_PART}
    sgdisk -ge "$LOOPDEV"

    if [ "$BOARD" == "radxa_zero_3w" ]; then
        local config_part_num=1
        local config_part_type
        config_part_type=$(lsblk -o PARTTYPE "${LOOPDEV}p${config_part_num}")
        [ "$config_part_type" == "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7" ] || sgdisk --typecode=${config_part_num}:0700 "$LOOPDEV"
    fi

    parted -s "$LOOPDEV" resizepart "$ROOT_PART" 100%
    e2fsck -yf "$ROOT_DEV"
    resize2fs "$ROOT_DEV"

    [ -d "$ROOTFS" ] || mkdir "$ROOTFS"
    mount "$ROOT_DEV" "$ROOTFS"

    if [ "$BOARD" == "radxa_zero_3w" ]; then
        mount "${LOOPDEV}p1" "$ROOTFS/config"
    fi

    mount -t proc /proc "$ROOTFS/proc"
    mount -t sysfs /sys "$ROOTFS/sys"
    mount -o bind /dev "$ROOTFS/dev"
    mount -o bind /run "$ROOTFS/run"
    mount -t devpts devpts "$ROOTFS/dev/pts"

    if [ "$BOARD" == "radxa_zero_3w" ]; then
        local config_partition_uuid
        config_partition_uuid=$(grep -oP "(?<=^UUID=).*(?=\s/config)" "${ROOTFS}/etc/fstab" | tr -d -)
        [ -d config_tmp ] || mkdir config_tmp
        cp -a "$ROOTFS/config/"* config_tmp/
        umount "$ROOTFS/config"
        mkfs.fat -F 16 -n config -i "${config_partition_uuid}" "${LOOPDEV}p1"
        mount "${LOOPDEV}p1" "$ROOTFS/config"
        mv config_tmp/* "$ROOTFS/config/"
        rmdir config_tmp
    fi
}

#
# Builds the image in chroot
#
build_in_chroot() {
    echo_blue "Building in chroot..."
    cd "$BUILD_DIR"

    mkdir -p "$ROOTFS/root/SourceCode/SBC-GS"
    cp -r ../gs ../pics "$ROOTFS/root/SourceCode/SBC-GS"
    cp *.sh "$ROOTFS/root/"
    chroot "$ROOTFS" env BOARD="$BOARD" /root/build.sh
    rm "$ROOTFS/root/"*.sh
}

#
# Generates the release info file
#
generate_release_info() {
    echo_blue "Generating release info..."
    cd "$BUILD_DIR"

    local build_date
    build_date=$(date "+%Y-%m-%d")
    local build_datetime
    build_datetime=$(date "+%Y-%m-%d %H:%M:%S")
    local version
    local channel

    if [[ "$GIT_REF" == refs/tags/* ]]; then
        version=${GIT_REF#refs/tags/}
        channel="release"
    else
        version=${COMMIT_SHA:0:7}
        channel="test"
    fi

    local release_file="$ROOTFS/etc/gs-release"
    echo "SBC_MODEL=\"$BOARD\"" > "$release_file"
    echo "BUILD_DATETIME=\"$build_datetime\"" >> "$release_file"
    echo "COMMIT=\"$COMMIT_SHA\"" >> "$release_file"
    echo "CHANNEL=\"$channel\"" >> "$release_file"
    echo "VERSION=\"$version\"" >> "$release_file"

    echo "============== show gs-release ============"
    cat "$release_file"
}

#
# Cleans up the build environment
#
cleanup() {
    echo_blue "Cleaning up..."
    set +e # Allow cleanup to continue even if some commands fail
    if mount | grep -q "${BUILD_DIR}/${ROOTFS}"; then
        mount | grep "${BUILD_DIR}/${ROOTFS}" | awk '{print $3}' | sort -r | xargs -I {} umount -R {}
    fi
    if [ -n "$LOOPDEV" ] && losetup -a | grep -q "$LOOPDEV"; then
        losetup -d "$LOOPDEV"
    fi
    if [ -d "$ROOTFS" ]; then
        rm -r "$ROOTFS"
    fi
    echo_green "Cleanup complete."
}

#
# Shrinks the image and cleans up the build environment
#
shrink_and_compress() {
    echo_blue "Shrinking and compressing image..."
    cd "$BUILD_DIR"

    # Get information from the loop device before unmounting
    local start_sector
    start_sector=$(sgdisk -i "$ROOT_PART" "$LOOPDEV" | grep "First sector:" | cut -d ' ' -f 3)
    local sector_size
    sector_size=$(blockdev --getss "$LOOPDEV")

    # Unmount filesystems before shrinking
    if mount | grep -q "${BUILD_DIR}/${ROOTFS}"; then
        mount | grep "${BUILD_DIR}/${ROOTFS}" | awk '{print $3}' | sort -r | xargs -I {} umount -R {}
    fi

    # Shrink filesystem
    e2fsck -yf "$ROOT_DEV"
    resize2fs -M "$ROOT_DEV"

    local block_size
    block_size=$(tune2fs -l "$ROOT_DEV" | grep '^Block size:' | tr -s ' ' | cut -d ' ' -f 3)
    local blocks_count
    blocks_count=$(tune2fs -l "$ROOT_DEV" | grep '^Block count:' | tr -s ' ' | cut -d ' ' -f 3)

    local new_part_size_sectors
    new_part_size_sectors=$(((blocks_count * block_size) / sector_size))
    local new_last_sector
    new_last_sector=$((start_sector + new_part_size_sectors - 1))

    # Detach loop device before resizing partition table
    if [ -n "$LOOPDEV" ] && losetup -a | grep -q "$LOOPDEV"; then
        losetup -d "$LOOPDEV"
    fi

    # Resize partition
    sgdisk --move-second-header "$IMAGE"
    sgdisk -e "$IMAGE"
    parted -s "$IMAGE" resizepart "$ROOT_PART" "${new_last_sector}s"

    local final_img_size_bytes
    final_img_size_bytes=$(((new_last_sector + 2) * sector_size))

    truncate -s "$final_img_size_bytes" "$IMAGE"
    sgdisk -v "$IMAGE"

    echo_green "Image shrunk."

    # Compress image
    local build_date
    build_date=$(date "+%Y-%m-%d")
    local version
    if [[ "$GIT_REF" == refs/tags/* ]]; then
        version=${GIT_REF#refs/tags/}
    else
        version=${COMMIT_SHA:0:7}
    fi
    xz -v -T0 "$IMAGE"
    
    local compressed_image="${IMAGE}.xz"
    if [ ! -s "$compressed_image" ]; then
        echo_red "Error: Compressed image not found or is empty."
        exit 1
    fi

    local final_image_name="Radxa-Zero-3_GroundStation_${build_date}_${version}.img.xz"
    mv "$compressed_image" "$final_image_name"

    echo_green "Build successful! Final image: $final_image_name"
}

#
# Main function
#
main() {
    if [ "$(id -u)" -ne 0 ]; then
        echo_red "This script must be run as root."
        exit 1
    fi

    echo_blue "Installing dependencies..."
    sudo apt update && sudo apt install -y wget xz-utils p7zip-full gdisk parted e2fsprogs dosfstools
    
    trap cleanup EXIT
    get_image
    expand_and_mount_image
    build_in_chroot
    generate_release_info
    shrink_and_compress
}

main "$@"
