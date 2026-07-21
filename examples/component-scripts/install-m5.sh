#!/bin/bash -eux
#
# EXAMPLE component script (belongs in the simbricks-gem5 component repo).
#
# Builds the gem5 'm5' guest tool from the SimBricks gem5 fork at a pinned ref
# and installs it as /sbin/m5. The ref MUST match the gem5 build that will run
# the image, because the m5 op ABI is tied to the simulator.
#
# Pass it to the harness via -var 'scripts=[..., "path/to/install-m5.sh"]'.

set -eux
export DEBIAN_FRONTEND=noninteractive

: "${M5_REPO:=https://github.com/simbricks/gem5.git}"
: "${M5_REF:=main}"

apt-get install -y --no-install-recommends scons python3   # build-essential from base

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
git clone --depth 1 --branch "$M5_REF" "$M5_REPO" "$W/gem5"
make -C "$W/gem5/util/m5" build/x86/out/m5 2>/dev/null \
  || ( cd "$W/gem5/util/m5" && scons build/x86/out/m5 )
install -m0755 "$W/gem5/util/m5/build/x86/out/m5" /sbin/m5

apt-get remove -y --purge scons
