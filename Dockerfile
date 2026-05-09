# Dockerfile
FROM ubuntu:24.04

# Avoid prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install build tools and handle multi-arch for GRUB binaries
RUN apt-get update && apt-get install -y ca-certificates curl gnupg && \
    DPKG_ARCH=$(dpkg --print-architecture) && \
    if [ "$DPKG_ARCH" = "arm64" ]; then \
        dpkg --add-architecture amd64 && \
        # Handle classic sources.list
        if [ -f /etc/apt/sources.list ]; then sed -i "s/^deb /deb [arch=arm64] /" /etc/apt/sources.list; fi && \
        # Handle new DEB822 sources
        if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then sed -i "s/^Types: deb/Architectures: arm64\nTypes: deb/" /etc/apt/sources.list.d/ubuntu.sources; fi && \
        echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse" > /etc/apt/sources.list.d/amd64.list && \
        echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse" >> /etc/apt/sources.list.d/amd64.list && \
        echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble-security main restricted universe multiverse" >> /etc/apt/sources.list.d/amd64.list; \
    elif [ "$DPKG_ARCH" = "amd64" ]; then \
        dpkg --add-architecture arm64 && \
        if [ -f /etc/apt/sources.list ]; then sed -i "s/^deb /deb [arch=amd64] /" /etc/apt/sources.list; fi && \
        if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then sed -i "s/^Types: deb/Architectures: amd64\nTypes: deb/" /etc/apt/sources.list.d/ubuntu.sources; fi && \
        echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble main restricted universe multiverse" > /etc/apt/sources.list.d/arm64.list && \
        echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble-updates main restricted universe multiverse" >> /etc/apt/sources.list.d/arm64.list && \
        echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble-security main restricted universe multiverse" >> /etc/apt/sources.list.d/arm64.list; \
    fi && \
    apt-get update && apt-get install -y \
    debootstrap \
    qemu-utils \
    qemu-user-static \
    binfmt-support \
    xorriso \
    grub-pc-bin:amd64 \
    grub-efi-amd64-bin:amd64 \
    grub-efi-arm64-bin:arm64 \
    mtools \
    dosfstools \
    squashfs-tools \
    parted \
    util-linux \
    e2fsprogs \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/ /scripts/
COPY configs/ /build/configs/
WORKDIR /build
ENTRYPOINT ["/scripts/build.sh"]
