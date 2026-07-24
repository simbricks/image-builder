#!/bin/bash -eux
#
# EXAMPLE corundum mqnic stage (belongs in the corundum component repo).
#
# Builds the mqnic driver against the installed kernel and autoloads it.
set -eux
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends build-essential

# Build against whatever kernel the harness set up (generic or a custom-built one);
# its build tree is under /lib/modules/<ver>/build. Not uname -r — the guest still
# runs the cloud kernel during provisioning.
KDIR=$(ls -d /lib/modules/*/build | sort -V | tail -1)
KVER=$(basename "$(dirname "$KDIR")")

# corundum sources (submodule holds the driver)
CORUNDUM_FOLDER="/tmp/component-corundum"
git clone https://github.com/simbricks/component-corundum.git "$CORUNDUM_FOLDER"
git -C "$CORUNDUM_FOLDER" submodule update --init

make -C "$CORUNDUM_FOLDER" driver-install KDIR="$KDIR" KVER="$KVER"
echo mqnic > /etc/modules-load.d/simbricks-mqnic.conf   # autoload on boot
