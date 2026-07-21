#!/bin/sh
#
# Harness-owned, host side. Copies boot artifacts out of the finished image
# via libguestfs, so simulators can be handed a kernel/initrd on the command
# line without virt-tools at run time.
#
#   Usage: extract-boot-artifacts.sh <disk.raw> <out-dir>      (env: WITH_HEADERS)
#
# Produces, under <out-dir>/boot/:
#   vmlinuz   distro kernel (bzImage)  -> lets you override the -kernel cmdline
#   initrd    distro initramfs         -> lets you override the -initrd cmdline
#   vmlinux   distro kernel (ELF)      -> lets you override the -kernel cmdline
#
# With WITH_HEADERS=true also <out>/boot/config and <out>/headers/ (escape hatch
# for host-side builds).
#
# Requires libguestfs tools on the host (virt-ls, virt-copy-out).
set -eu

IMG="$1"
OUT="$2"
WITH_HEADERS="${WITH_HEADERS:-false}"
mkdir -p "$OUT/boot"
export LIBGUESTFS_BACKEND=direct   # no libvirtd needed; good in CI/containers

# Kernel version = suffix of the single vmlinuz-* in /boot
KVER=$(virt-ls -a "$IMG" /boot | grep -m1 '^vmlinuz-' | sed 's/^vmlinuz-//')
if [ -z "$KVER" ]; then
    echo "ERROR: no /boot/vmlinuz-* found in $IMG" >&2
    exit 1
fi
echo "Extracting boot artifacts for kernel ${KVER}"

# bzImage + initramfs (always present in a distro image)
virt-copy-out -a "$IMG" \
    "/boot/vmlinuz-${KVER}" \
    "/boot/initrd.img-${KVER}" \
    "$OUT/boot/"
mv "$OUT/boot/vmlinuz-${KVER}"    "$OUT/boot/vmlinuz"
mv "$OUT/boot/initrd.img-${KVER}" "$OUT/boot/initrd"

# ELF vmlinux from the -dbg package, if install-boot-artifacts.sh installed it
if virt-ls -a "$IMG" /usr/lib/debug/boot 2>/dev/null | grep -q "^vmlinux-${KVER}$"; then
    virt-copy-out -a "$IMG" "/usr/lib/debug/boot/vmlinux-${KVER}" "$OUT/boot/"
    mv "$OUT/boot/vmlinux-${KVER}" "$OUT/boot/vmlinux"
    echo "  -> boot/vmlinux (ELF, for gem5)"
else
    echo "  -> boot/vmlinux NOT produced (no -dbg kernel in image); gem5 unusable with this image" >&2
fi

# Optional kernel config + headers build tree, for host-side module builds.
if [ "$WITH_HEADERS" = true ]; then
    virt-copy-out -a "$IMG" "/boot/config-${KVER}" "$OUT/boot/"
    mv "$OUT/boot/config-${KVER}" "$OUT/boot/config"
    echo "  -> boot/config"
    if virt-ls -a "$IMG" /usr/src 2>/dev/null | grep -q "linux-headers-${KVER}"; then
        rm -rf "$OUT/headers" "$OUT/src"
        virt-copy-out -a "$IMG" /usr/src "$OUT/"
        mv "$OUT/src" "$OUT/headers"
        echo "  -> headers/ (linux-headers build tree)"
    else
        echo "  -> headers/ NOT produced (no linux-headers in image)" >&2
    fi
fi
