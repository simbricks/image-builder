#!/bin/sh
#
# Harness-owned, guest side. Installs the kernel packages whose files
# extract-boot-artifacts.sh later copies out of the image. Gated by env flags:
#   WITH_VMLINUX=true   install the -dbg kernel (ships the ELF vmlinux)
#   WITH_HEADERS=true   install the linux-headers build tree (for host module builds)
#
# No kernel is built here; both are the distro's own packages.
set -eu

WITH_VMLINUX="${WITH_VMLINUX:-true}"
WITH_HEADERS="${WITH_HEADERS:-false}"
export DEBIAN_FRONTEND=noninteractive
set -x

KVER=$(uname -r)
apt-get update

# ELF vmlinux for gem5: the -dbg package ships /usr/lib/debug/boot/vmlinux-$KVER.
if [ "$WITH_VMLINUX" = true ]; then
    if ! apt-get install -y --no-install-recommends "linux-image-${KVER}-dbg"; then
        echo "WARN: no linux-image-${KVER}-dbg available; boot/vmlinux will be missing" >&2
        echo "WARN: gem5 host components will not be able to use this image"            >&2
    fi
fi

# linux-headers build tree, kept in the image only so it can be extracted for
# building out-of-tree modules on the host (enlarges the image).
if [ "$WITH_HEADERS" = true ]; then
    apt-get install -y --no-install-recommends "linux-headers-${KVER}"
fi
