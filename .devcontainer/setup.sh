#!/usr/bin/env bash

set -eux
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    qemu-system-x86 \
    qemu-utils \
    libguestfs-tools \
    linux-image-amd64 \
    make \
    git \
    ca-certificates \
    curl \
    unzip

rm -rf /var/lib/apt/lists/*

# packer from the official release archive (the qemu plugin is fetched by
# `packer init` / `make init` on first build).
PACKER_VERSION=1.11.2
curl -fsSL "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip" \
    -o /tmp/packer.zip
unzip -o -d /usr/local/bin /tmp/packer.zip
rm /tmp/packer.zip

# libguestfs' 'direct' backend (used by extract-boot-artifacts.sh) builds its
# appliance from the installed kernel and must be able to read it; Debian ships
# /boot/vmlinuz-* mode 0600.
chmod 0644 /boot/vmlinuz-* 2>/dev/null || true
