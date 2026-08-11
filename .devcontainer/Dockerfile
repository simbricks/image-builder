# jammy: same GCC (11) as the guest, so the kernel built here and the modules the
# guest builds against it share a compiler (no modpost mismatch).
FROM mcr.microsoft.com/devcontainers/base:jammy

ARG DEBIAN_FRONTEND=noninteractive
ARG PACKER_VERSION=1.11.2

RUN apt-get update && apt-get install -y --no-install-recommends \
        qemu-system-x86 \
        qemu-utils \
        build-essential \
        patch \
        git \
        ca-certificates \
        curl \
        unzip \
        flex \
        bison \
        libelf-dev \
        libssl-dev \
        bc \
        cpio \
        kmod \
        dpkg-dev \
        rsync \
        fakeroot \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

# packer from the official release archive.
RUN curl -fsSL "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip" \
        -o /tmp/packer.zip \
    && unzip -o -d /usr/local/bin /tmp/packer.zip \
    && rm /tmp/packer.zip
