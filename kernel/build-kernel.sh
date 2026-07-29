#!/bin/bash -eux
#
# Build a custom no-initrd kernel outside packer (`make kernel`). Produces in $OUT:
#   vmlinux             uncompressed ELF (e.g. gem5 --kernel)
#   linux-image-*.deb   kernel + modules
#   linux-headers-*.deb build tree for out-of-tree drivers
# Feed $OUT to `make image INPUT=$OUT ...` with install-kernel.sh.
#
# Config and timer patch are pinned to 5.15.93 so config, patch and source match; the
# result boots with no initrd and runs under gem5. Build in the jammy devcontainer so
# the kernel and the guest's out-of-tree modules share a compiler (gcc 11).
set -eux

VER=5.15.93
OUT=$(readlink -f "${OUT:-output/kernel}")
HERE=$(cd "$(dirname "$0")" && pwd)

mkdir -p "$OUT"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v${VER%%.*}.x/linux-$VER.tar.xz" | tar -xJ -C "$work"
cd "$work/linux-$VER"

# gem5 miscalibrates the LAPIC timer / TSC; adds lapic_timer_period= / tsc_override_freq=
patch -p1 < "$HERE/linux-5.15.93-timers-gem5.patch"

cp "$HERE/config-5.15.93" .config
make olddefconfig

make -j"$(nproc)" bindeb-pkg
cp vmlinux "$OUT/"
mv "$work"/linux-image-*.deb "$work"/linux-headers-*.deb "$OUT/"

echo "kernel $VER -> $OUT:"; ls -1 "$OUT"
