#!/bin/bash -eux
#
# EXAMPLE gem5 kernel stage (belongs in the gem5 component repo). Replaces
# scripts/install-boot-artifacts.sh: installs the kernel from `make gem5-kernel`, passed
# via INPUT (-> /tmp/input) as the linux-image/-headers debs and the vmlinux ELF.
# A later component stage (mqnic, ...) builds against /lib/modules/<ver>/build.
set -eux
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends /tmp/input/linux-image-*.deb /tmp/input/linux-headers-*.deb

# Boot this kernel only: drop the -kvm cloud kernel.
kvm=$(dpkg-query -W -f='${Package}\n' 'linux-*-kvm' 2>/dev/null || true)
[ -n "$kvm" ] && apt-get purge -y $kvm
update-grub

# Stage the ELF vmlinux (gem5 --kernel) where extract-boot-artifacts.sh copies it.
kver=$(ls /boot/vmlinuz-* | sed 's|.*/vmlinuz-||' | sort -V | tail -1)
mkdir -p /usr/lib/debug/boot
cp /tmp/input/vmlinux "/usr/lib/debug/boot/vmlinux-$kver"
