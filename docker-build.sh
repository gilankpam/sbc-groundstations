#!/usr/bin/env bash
set -e

# Configuration
IMAGE_NAME="openipc-gs-builder"
DOCKERfile="Dockerfile"
PWD=$(pwd)

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -c <defconfig>  Specify the defconfig to use (default: runcam_wifilink_defconfig)"
    echo "  -h              Show this help message"
    exit 1
}

# Parse command line arguments
DEFCONFIG="runcam_wifilink_defconfig"

while getopts "c:h" opt; do
    case $opt in
        c) DEFCONFIG=$OPTARG ;;
        h) usage ;;
        *) usage ;;
    esac
done

echo "Building Docker image..."
if command -v docker >/dev/null 2>&1; then
    docker build -t $IMAGE_NAME -f $DOCKERfile .
elif command -v podman >/dev/null 2>&1; then
    podman build -t $IMAGE_NAME -f $DOCKERfile .
else
    echo "Error: Neither docker nor podman found."
    exit 1
fi

echo "Running build for $DEFCONFIG..."

# Determine the container engine
if command -v docker >/dev/null 2>&1; then
    ENGINE="docker"
else
    ENGINE="podman"
fi

# Run the build container
$ENGINE run --rm -it \
    -v "$PWD:/project" \
    -v /etc/passwd:/etc/passwd:ro \
    -v /etc/group:/etc/group:ro \
    -e DEFCONFIG="$DEFCONFIG" \
    -e HOME=/tmp \
    -e USER=$(whoami) \
    --user $(id -u):$(id -g) \
    $IMAGE_NAME ./build.sh
