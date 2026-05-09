# Ubuntu Kenzen Builder

An automated, containerized pipeline for building highly customized, bloat-free ("kenzen") Ubuntu disk images. It supports building both `amd64` and `arm64` architectures, for `MBR` and `UEFI` boot modes.

The build pipeline leverages a **privileged loop-device architecture** within Docker, ensuring reliable cross-platform compatibility across local environments (like macOS Docker Desktop) and CI/CD systems (like GitHub Actions).

## 🌟 Key Features

*   **"Kenzen" (Bloat-Free):** Aggressively pins and prevents bloatware such as `ubuntu-pro`, `snapd`, `apparmor`, and `systemd-oomd` via custom APT configurations.
*   **Architecture Agnostic:** Supports cross-compiling `amd64` and `arm64` targets dynamically relying on QEMU and Docker.
*   **Cloud-Ready:** Includes base `cloud-init` configurations so images are ready for deployment on first boot.

## 📂 Project Structure

- `Dockerfile`: The isolated build environment containing all necessary OS-building tools (`debootstrap`, `qemu-utils`, `parted`, etc.).
- `scripts/build.sh`: The core orchestration script that handles disk creation, partitioning, loop device mounting, `debootstrap`, and GRUB configuration.
- `configs/no-bloat`: APT preferences configuration used to block unwanted packages.
- `configs/cloud-init-defaults`: Base configurations to ensure smooth first-boot experiences.


## 🚀 How to Build Locally

The image orchestration is fully functional and can be run locally via Docker.

> [!IMPORTANT]
> **Privileged Mode**: Running the build script requires `--privileged` mode to allow loop device management and mounting within the container. Docker Desktop on Mac fully supports this because it runs a lightweight Linux VM in the background.

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

*Note: You can swap `--boot uefi` with `--boot mbr` if legacy BIOS support is needed.*

The output will be found as a mountable `.img` file (e.g., `ubuntu-amd64-uefi.img`) in your `./output` directory.

