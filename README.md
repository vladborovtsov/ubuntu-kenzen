# Ubuntu Kenzen Builder

An automated, containerized pipeline to build highly customized, bloat-free ("kenzen") Ubuntu disk images. It supports building both `amd64` and `arm64` architectures, for `MBR` and `UEFI` boot modes. 

The build pipeline leverages a **privileged loop-device architecture** within Docker, ensuring cross-platform compatibility across local environments (like macOS Docker Desktop) and CI/CD systems (like GitHub Actions).

## Project Structure

- `Dockerfile`: The isolated environment containing all necessary OS-building tools (`debootstrap`, `qemu-utils`, `parted`, etc.).
- `scripts/build.sh`: The core orchestration script that partitions raw images, runs `debootstrap`, and configures GRUB.
- `configs/`:
    - `no-bloat`: APT configuration that aggressively pins and prevents bloatware (like `snapd`, `apparmor`, and `systemd-oomd`) from being installed.
    - `cloud-init-defaults`: Base configurations to ensure the images are cloud-ready on first boot.

## The Architecture & Technical Fixes

Our builder runs in privileged Docker containers. We chose this over a rootless `mmdebstrap` approach to ensure reliable cross-architecture compiling (e.g., building `amd64` images on an `arm64` host).

### Final Technical Fixes
1. **Loop Device Node Mapping:** Docker containers (especially FUSE/macOS implementations) do not automatically trigger `udev` to populate `/dev/loopXpY` partition nodes when an image is mounted. To bypass this kernel limitation, we query `/sys/block/` and use `mknod` to manually generate the block devices for formatting (`mkfs.vfat` and `mkfs.ext4`).
2. **Disk Capacity:** An Ubuntu 24.04 (Noble) system requires a substantial amount of space. We increased the default generated `DISK_SIZE` from `2G` to `4G` to prevent `debootstrap` from running out of space when unpacking massive dependencies like `linux-firmware`.
3. **Chroot POSIX Compliance:** Inside the chroot environment, Ubuntu relies on `dash` rather than `bash`. We updated our `if` string comparisons (`=` instead of `==`) to prevent "unexpected operator" errors.
4. **GRUB Architecture Targeting:** We correctly mapped the host script architecture (`amd64` / `arm64`) to GRUB's internal EFI targets (`x86_64-efi` / `arm64-efi`) to ensure `grub-install` successfully initializes the boot sector.
5. **Ubuntu Package Archives:** Ubuntu splits its package repositories by architecture. We dynamically swap the `debootstrap` mirror from `archive.ubuntu.com` (for `amd64`) to `ports.ubuntu.com` (for `arm64`) to ensure packages are successfully located during the build.

## How to Build

The image orchestration is fully functioning.

### Build for AMD64 (Standard PCs/Servers)
```bash
docker build -t image-builder .
docker run --privileged -v $(pwd)/output:/output image-builder --arch amd64 --boot uefi
```

### Build for ARM64 (Raspberry Pi, Apple Silicon, ARM Servers)
```bash
docker build -t image-builder .
docker run --privileged -v $(pwd)/output:/output image-builder --arch arm64 --boot uefi
```

The output will be found as a mountable `.img` file in your `./output` directory.

### GitHub Actions

The images are automatically built on every tag push or via manual trigger.

> [!IMPORTANT]
> **Privileged Mode**: Running the build script requires `--privileged` mode to allow loop device management and mounting within the container. Docker Desktop on Mac fully supports this because it runs a lightweight Linux VM in the background.
