#!/bin/bash -eux
#
# Build the gem5 kernel outside packer (`make gem5-kernel`). Produces in $OUT:
#   vmlinux             ELF for gem5 --kernel
#   linux-image-*.deb   kernel + modules
#   linux-headers-*.deb build tree for out-of-tree drivers
# Feed $OUT to `make image INPUT=$OUT ...` with install-gem5-kernel.sh.
#
# Config constraints:
#   - gem5 boots the ELF with no initrd, so disk (PIIX IDE), root fs and serial
#     console must be built in (=y).
#   - mqnic links the devlink core and needs devlink_port_attrs_set() (>= 5.9), so
#     we build 5.15 (jammy's series). NET_DEVLINK isn't promptable; NETDEVSIM
#     selects it.
# Built in the jammy devcontainer so the kernel and the guest's modules share a
# compiler (gcc 11).
set -eux

VER="${VER:-5.15.148}"
OUT=$(readlink -f "${OUT:-output/kernel}")

mkdir -p "$OUT"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v${VER%%.*}.x/linux-$VER.tar.xz" | tar -xJ -C "$work"
cd "$work/linux-$VER"

make defconfig

scripts/config -d DEBUG_INFO           # no -dbg package; gem5 reads .symtab
# no-initrd boot path
scripts/config -e EXT4_FS -e ATA -e ATA_PIIX -e SERIAL_8250 -e SERIAL_8250_CONSOLE
# devlink core (via NETDEVSIM) + PTP clock, for mqnic
scripts/config -m NETDEVSIM -e PTP_1588_CLOCK
make olddefconfig

make -j"$(nproc)" bindeb-pkg
cp vmlinux "$OUT/"
mv "$work"/linux-image-*.deb "$work"/linux-headers-*.deb "$OUT/"

echo "gem5 kernel $VER -> $OUT:"; ls -1 "$OUT"
