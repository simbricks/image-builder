#!/bin/sh
#
# Harness-owned (guest): stage the boot artifacts into /tmp/boot-artifacts.tar.gz
# so packer's file provisioner can download them over SSH.
set -eu
WITH_VMLINUX="${WITH_VMLINUX:-true}"
d=$(mktemp -d)

kver=$(ls /boot/vmlinuz-* | sed 's|.*/vmlinuz-||' | sort -V | tail -1)
cp "/boot/vmlinuz-$kver" "$d/vmlinuz"
if [ -f "/boot/initrd.img-$kver" ]; then cp "/boot/initrd.img-$kver" "$d/initrd"; fi

# uncompressed ELF vmlinux (for gem5), wherever the kernel stage left it
if [ "$WITH_VMLINUX" = true ]; then
    for v in "/usr/lib/debug/boot/vmlinux-$kver" "/boot/vmlinux-$kver"; do
        if [ -f "$v" ]; then cp "$v" "$d/vmlinux"; break; fi
    done
fi

tar czf /tmp/boot-artifacts.tar.gz -C "$d" .
chmod a+r /tmp/boot-artifacts.tar.gz   # so the (non-root) SSH user can download it
echo "staged for $kver: $(tar tzf /tmp/boot-artifacts.tar.gz | tr '\n' ' ')"
rm -rf "$d"
