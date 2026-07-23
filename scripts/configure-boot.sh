#!/bin/bash -eux
#
# Boot-speed tweaks for the generated image: no OS prober, no GRUB menu delay
# (boot should go straight to the kernel).

set -eux

GRUB_CFG=/etc/default/grub.d/50-cloudimg-settings.cfg
{
    echo 'GRUB_DISABLE_OS_PROBER=true'
    echo 'GRUB_HIDDEN_TIMEOUT=0'
    echo 'GRUB_TIMEOUT=0'
} >> "$GRUB_CFG"
update-grub
