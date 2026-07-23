#!/bin/sh
#
# Harness-owned (host): copy boot artifacts out of the image via libguestfs.
#   Usage: extract-boot-artifacts.sh <disk.raw> <out-dir>
# Produces <out>/boot/{vmlinuz,initrd,vmlinux}. Needs libguestfs (virt-ls,
# virt-copy-out).
set -eu

IMG="$1"
OUT="$2"
WITH_VMLINUX="${WITH_VMLINUX:-true}"
mkdir -p "$OUT/boot"
export LIBGUESTFS_BACKEND=direct

KVER=$(virt-ls -a "$IMG" /boot | grep '^vmlinuz-' | sed 's/^vmlinuz-//' | sort -V | tail -1)
if [ -z "$KVER" ]; then
    echo "ERROR: no /boot/vmlinuz-* found in $IMG" >&2
    exit 1
fi
echo "Extracting boot artifacts for kernel ${KVER}"

virt-copy-out -a "$IMG" \
    "/boot/vmlinuz-${KVER}" \
    "/boot/initrd.img-${KVER}" \
    "$OUT/boot/"
mv "$OUT/boot/vmlinuz-${KVER}"    "$OUT/boot/vmlinuz"
mv "$OUT/boot/initrd.img-${KVER}" "$OUT/boot/initrd"

# ELF vmlinux the guest decompressed with extract-vmlinux (when install_vmlinux)
if [ "$WITH_VMLINUX" = true ]; then
    if virt-ls -a "$IMG" /usr/lib/debug/boot 2>/dev/null | grep -q "^vmlinux-${KVER}$"; then
        virt-copy-out -a "$IMG" "/usr/lib/debug/boot/vmlinux-${KVER}" "$OUT/boot/"
        mv "$OUT/boot/vmlinux-${KVER}" "$OUT/boot/vmlinux"
        echo "  -> boot/vmlinux (uncompressed ELF)"
    else
        echo "  -> boot/vmlinux NOT produced" >&2
    fi
fi
