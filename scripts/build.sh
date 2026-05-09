#!/bin/bash
set -e

# Default values
ARCH="amd64"
BOOT="uefi"
RELEASE="noble"
DISK_SIZE="4G"
OUTPUT_DIR="/output"
BUILD_DIR="/tmp/build"
CONFIGS_DIR="/build/configs"

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --arch) ARCH="$2"; shift ;;
        --boot) BOOT="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

echo "Building Ubuntu $RELEASE image for $ARCH ($BOOT)..."

# Ensure clean build environment
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

IMAGE_NAME="ubuntu-${ARCH}-${BOOT}.img"
IMAGE_PATH="${BUILD_DIR}/${IMAGE_NAME}"

# 1. Create disk image
qemu-img create -f raw "$IMAGE_PATH" "$DISK_SIZE"

# 2. Partitioning
if [ "$BOOT" == "uefi" ]; then
    # GPT for UEFI
    parted -s "$IMAGE_PATH" mklabel gpt
    parted -s "$IMAGE_PATH" mkpart ESP fat32 1MiB 513MiB
    parted -s "$IMAGE_PATH" set 1 esp on
    parted -s "$IMAGE_PATH" mkpart root ext4 513MiB 100%
else
    # MBR for BIOS
    parted -s "$IMAGE_PATH" mklabel msdos
    parted -s "$IMAGE_PATH" mkpart primary ext4 1MiB 100%
    parted -s "$IMAGE_PATH" set 1 boot on
fi

# 3. Setup loop device
LOOP_DEV=$(losetup --show -fP "$IMAGE_PATH")
trap "losetup -d $LOOP_DEV" EXIT

# Docker /dev workaround: manually create partition nodes if missing
LOOP_NAME=$(basename "$LOOP_DEV")
sleep 1 # Give kernel a moment to populate sysfs
if [ ! -e "${LOOP_DEV}p1" ] && [ -f "/sys/block/${LOOP_NAME}/${LOOP_NAME}p1/dev" ]; then
    IFS=':' read -r major minor < "/sys/block/${LOOP_NAME}/${LOOP_NAME}p1/dev"
    mknod "${LOOP_DEV}p1" b "$major" "$minor"
fi
if [ ! -e "${LOOP_DEV}p2" ] && [ -f "/sys/block/${LOOP_NAME}/${LOOP_NAME}p2/dev" ]; then
    IFS=':' read -r major minor < "/sys/block/${LOOP_NAME}/${LOOP_NAME}p2/dev"
    mknod "${LOOP_DEV}p2" b "$major" "$minor"
fi

# 4. Format partitions
if [ "$BOOT" == "uefi" ]; then
    mkfs.vfat -F 32 "${LOOP_DEV}p1"
    mkfs.ext4 -F "${LOOP_DEV}p2"
    PART_ROOT="${LOOP_DEV}p2"
    PART_ESP="${LOOP_DEV}p1"
else
    mkfs.ext4 -F "${LOOP_DEV}p1"
    PART_ROOT="${LOOP_DEV}p1"
fi

# 5. Mount partitions
CHROOT_DIR="${BUILD_DIR}/chroot"
mkdir -p "$CHROOT_DIR"
mount "$PART_ROOT" "$CHROOT_DIR"
trap "umount -l $CHROOT_DIR; losetup -d $LOOP_DEV" EXIT

if [ "$BOOT" == "uefi" ]; then
    mkdir -p "${CHROOT_DIR}/boot/efi"
    mount "$PART_ESP" "${CHROOT_DIR}/boot/efi"
    trap "umount -l ${CHROOT_DIR}/boot/efi; umount -l $CHROOT_DIR; losetup -d $LOOP_DEV" EXIT
fi

# Run debootstrap
if [ "$ARCH" = "amd64" ]; then
    UBUNTU_MIRROR="http://archive.ubuntu.com/ubuntu/"
else
    UBUNTU_MIRROR="http://ports.ubuntu.com/ubuntu-ports/"
fi
debootstrap --arch="$ARCH" --include=linux-image-generic,initramfs-tools,grub-efi-${ARCH}-bin,cloud-init,sudo,network-manager "$RELEASE" "$CHROOT_DIR" "$UBUNTU_MIRROR"

# Correct grub package based on arch/boot
if [ "$ARCH" == "amd64" ]; then
    if [ "$BOOT" == "uefi" ]; then GRUB_PKG="grub-efi-amd64"; else GRUB_PKG="grub-pc"; fi
    GRUB_TARGET="x86_64-efi"
else
    if [ "$BOOT" == "uefi" ]; then GRUB_PKG="grub-efi-arm64"; else GRUB_PKG="grub-pc"; echo "MBR not well supported on arm64"; fi
    GRUB_TARGET="arm64-efi"
fi

# 7. Configure system (chroot)
mount --bind /dev "${CHROOT_DIR}/dev"
mkdir -p "${CHROOT_DIR}/dev/pts"
mount -t devpts devpts "${CHROOT_DIR}/dev/pts"
mount --bind /proc "${CHROOT_DIR}/proc"
mount --bind /sys "${CHROOT_DIR}/sys"
trap "umount -l ${CHROOT_DIR}/dev/pts ${CHROOT_DIR}/dev ${CHROOT_DIR}/proc ${CHROOT_DIR}/sys ${CHROOT_DIR}/boot/efi $CHROOT_DIR || true; losetup -d $LOOP_DEV || true" EXIT

# Copy configs
cp $CONFIGS_DIR/no-bloat "${CHROOT_DIR}/etc/apt/preferences.d/no-bloat"
cp $CONFIGS_DIR/cloud-init-defaults "${CHROOT_DIR}/etc/cloud/cloud.cfg.d/99-defaults.cfg"

# Chroot commands
cat <<EOF | chroot "$CHROOT_DIR"
set -e
# Set hostname
echo "ubuntu-kenzen" > /etc/hostname

# Configure GRUB to pass framebuffer to kernel for monitor output, disable splash
mkdir -p /etc/default/grub.d
cat << 'EOF_GRUB' > /etc/default/grub.d/99-custom.cfg
GRUB_CMDLINE_LINUX_DEFAULT="apparmor=0 fbcon=nodefer console=tty1"
GRUB_TERMINAL="gfxterm"
GRUB_GFXPAYLOAD_LINUX="keep"
EOF_GRUB

# FSTAB
ROOT_UUID=\$(blkid -s UUID -o value $PART_ROOT)
if [ "$BOOT" = "uefi" ]; then
    ESP_UUID=\$(blkid -s UUID -o value $PART_ESP)
    echo "UUID=\$ROOT_UUID / ext4 defaults 0 1" > /etc/fstab
    echo "UUID=\$ESP_UUID /boot/efi vfat defaults 0 2" >> /etc/fstab
else
    echo "UUID=\$ROOT_UUID / ext4 defaults 0 1" > /etc/fstab
fi

# Ensure initramfs is created/updated for the kernel and install GRUB
update-initramfs -c -k all || update-initramfs -u -k all
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y $GRUB_PKG

if [ "$BOOT" = "uefi" ]; then
    grub-install --target=$GRUB_TARGET --efi-directory=/boot/efi --bootloader-id=ubuntu --removable
else
    # MBR installation needs to point to the loop device (but without the partition number)
    # This is tricky inside a container/chroot. We'll do it from outside.
    echo "Skipping MBR grub-install inside chroot"
fi

update-grub

# Fix root partition in GRUB config to use UUID instead of build environment loop device
sed -i "s|root=/dev/loop[0-9]*p[0-9]*|root=UUID=\$ROOT_UUID|g" /boot/grub/grub.cfg
EOF

# Install MBR GRUB from outside if needed
if [ "$BOOT" = "mbr" ]; then
    grub-install --target=i386-pc --boot-directory="${CHROOT_DIR}/boot" "$LOOP_DEV"
fi

# Cleanup
umount -l "${CHROOT_DIR}"/{dev/pts,dev,proc,sys,boot/efi,} || true
losetup -d "$LOOP_DEV"
trap - EXIT

# Move to output
mv "$IMAGE_PATH" "$OUTPUT_DIR/"
echo "Build complete: ${OUTPUT_DIR}/${IMAGE_NAME}"
