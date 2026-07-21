#!/bin/bash -eux
#
# EXAMPLE component script (belongs in the simbricks-corundum component repo).
#
# Builds the Corundum mqnic driver against the IMAGE'S OWN kernel headers, so
# the module's vermagic matches the image kernel by construction — no version
# matrix, no cross-build container.
#
# Pass it to the harness via -var 'scripts=[..., "path/to/install-mqnic.sh"]'.
#
# NOTE: the module matches the DISTRO kernel in the image. If you run this image
# on the current gem5 fork with a *different* (e.g. gem5-resources) kernel, the
# module will not load there. On QEMU (which boots the image's own kernel) it
# works. See README.

set -eux
export DEBIAN_FRONTEND=noninteractive

: "${CORUNDUM_REPO:=https://github.com/corundum/corundum.git}"
: "${CORUNDUM_REF:=master}"   # pin to a known-good ref in real use

apt-get install -y --no-install-recommends "linux-headers-$(uname -r)"

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
git clone --depth 1 --branch "$CORUNDUM_REF" "$CORUNDUM_REPO" "$W/corundum"
make -C "$W/corundum/modules/mqnic" -j"$(nproc)"

KDIR="/lib/modules/$(uname -r)"
install -d "$KDIR/extra"
install -m0644 "$W/corundum/modules/mqnic/mqnic.ko" "$KDIR/extra/"
depmod -a "$(uname -r)"

# Autoload on boot; drop this if orchestration should insmod explicitly.
echo mqnic > /etc/modules-load.d/simbricks-mqnic.conf
