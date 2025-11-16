#!/bin/bash
# Must using Ubuntu 22.04，24.04 had issue with qemu-aarch64-static
# script running in target debian arm64 OS

set -e
set -x

export LANGUAGE=POSIX
export LC_ALL=POSIX
export LANG=POSIX

if [ -z "$BOARD" ]; then
    echo "BOARD is not set. Please set it in gs.conf"
    exit 1
fi

build_script_path=$(dirname $(readlink -f "$0"))
build_script="build-${BOARD}.sh"

if [ ! -f "$build_script_path/$build_script" ]; then
    echo "Build script for $BOARD not found at $build_script_path/$build_script"
    exit 1
fi

$build_script_path/$build_script