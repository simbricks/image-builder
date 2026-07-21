#!/bin/bash -eux
#
# Base guest software: the packages you want present in the generated image.
# This is the customization point — edit the list below to taste.

set -eux
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    iperf iputils-ping lbzip2 netperf netcat-openbsd ethtool tcpdump \
    pciutils busybox numactl sysbench time \
    ca-certificates curl git build-essential
