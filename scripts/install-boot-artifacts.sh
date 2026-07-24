#!/bin/sh
#
# Harness-owned (guest), runs before the component scripts: boot the full `generic`
# kernel instead of the stripped cloud/-kvm one (drivers like mqnic need config
# -kvm lacks, e.g. I2C), then decompress the ELF vmlinux for the host to copy out.
set -eux
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends linux-generic
kvm=$(dpkg-query -W -f='${Package}\n' 'linux-*-kvm' 2>/dev/null || true)
[ -n "$kvm" ] && apt-get purge -y $kvm
update-grub

# Decompress the ELF vmlinux into /usr/lib/debug/boot for extract-boot-artifacts.sh.
# extract-vmlinux comes from linux-headers; binutils + compressors do the unpacking.
if [ "${WITH_VMLINUX:-true}" = true ]; then
    kver=$(ls /boot/vmlinuz-* | sed 's|.*/vmlinuz-||' | sort -V | tail -1)
    apt-get install -y --no-install-recommends binutils xz-utils zstd lz4
    ev=$(ls /usr/src/linux-headers-*/scripts/extract-vmlinux | head -1)
    mkdir -p /usr/lib/debug/boot
    sh "$ev" "/boot/vmlinuz-$kver" > "/usr/lib/debug/boot/vmlinux-$kver"
    [ -s "/usr/lib/debug/boot/vmlinux-$kver" ] || rm -f "/usr/lib/debug/boot/vmlinux-$kver"
fi
