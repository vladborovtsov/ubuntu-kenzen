#!/bin/bash
set -e

# Change to the project root directory
cd "$(dirname "$0")/.."

echo "======================================"
echo " Building Docker builder environment  "
echo "======================================"
docker build -t image-builder .

echo "======================================"
echo " Building AMD64 (Standard PC) image   "
echo "======================================"
docker run --privileged -v "$(pwd)/output:/output" image-builder --arch amd64 --boot uefi

echo "======================================"
echo " Building ARM64 (Apple Silicon) image "
echo "======================================"
docker run --privileged -v "$(pwd)/output:/output" image-builder --arch arm64 --boot uefi

echo "======================================"
echo " All builds completed successfully!   "
echo " Images are located in ./output/      "
echo "======================================"
