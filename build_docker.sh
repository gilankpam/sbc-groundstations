#!/bin/bash
set -e

# This script builds and runs the project in a Docker container.
#
# Usage:
#   ./build_docker.sh [target]
#
# The DEFCONFIG environment variable can be set to choose the build configuration.
# For example:
#   DEFCONFIG=emax_wyvern-link_defconfig ./build_docker.sh all

echo "Building docker image for arm64 platform..."
docker build --platform linux/arm64 -t sbc-groundstations-build .

echo "Running build inside docker..."
docker run --rm --privileged \
    -v "$(pwd)":/project \
    -e DEFCONFIG \
    sbc-groundstations-build \
    ./build.sh "$@"
