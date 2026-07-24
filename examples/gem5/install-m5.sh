#!/bin/bash -eux
#
# EXAMPLE component script (belongs in the simbricks-gem5 component repo).
#
# Builds the gem5 'm5' guest tool from the SimBricks gem5 fork and installs it as
# /sbin/m5. The fork/ref MUST match the gem5 build that will run the image — the
# m5 op ABI is tied to the simulator.
set -eux
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends git scons build-essential python3

# Clone the fork (plus submodules, e.g. the gem5 source the m5 tool lives in).
GEM5_FOLDER="/tmp/component-gem5"
git clone https://github.com/simbricks/component-gem5.git "$GEM5_FOLDER"
git -C "$GEM5_FOLDER" submodule update --init --recursive

# Build + install m5 via the fork's Makefile targets (m5-install builds first).
# It installs under PREFIX at an ABI-qualified path; stage it, then drop the
# binary on PATH as /sbin/m5.
make -C "$GEM5_FOLDER" m5-install PREFIX=/tmp/m5-stage M5_ABI=x86 GEM5_JOBS="$(nproc)"
install -m0755 "$(find /tmp/m5-stage -type f -name m5 | head -1)" /sbin/m5
rm -rf /tmp/m5-stage

apt-get remove -y --purge scons
