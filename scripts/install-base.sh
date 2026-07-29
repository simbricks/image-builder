#!/bin/bash -eux
#
# Base packages baked into the image — the customization point; edit to taste.

set -eux
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    iperf iputils-ping lbzip2 netperf netcat-openbsd ethtool tcpdump \
    pciutils time curl
