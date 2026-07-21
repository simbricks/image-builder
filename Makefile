# Convenience wrappers around `packer build`. Everything here is optional — you
# can invoke packer directly (see README). Override any VAR on the command line:
#
#   make image SOURCE_IMAGE=https://.../debian-13-genericcloud-amd64.qcow2 \
#              SOURCE_CHECKSUM=file:https://.../SHA512SUMS

PACKER        ?= packer
SOURCE_IMAGE  ?= https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2
SOURCE_CHECKSUM ?= file:https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS
ACCELERATOR   ?= kvm

# Guest stages, run in order (space-separated paths). install-base is your
# software; configure-boot trims the GRUB delay; install-guestinit is the
# SimBricks payload runner. The kernel/boot artifacts (gem5's vmlinux, headers)
# are harness-owned and controlled by the flags below, not stages.
BASE_SCRIPTS  ?= scripts/install-base.sh scripts/configure-boot.sh scripts/install-guestinit.sh

# Extra component stages appended after the base ones. Point these at the
# component repos' install scripts, e.g.:
#   make image EXTRA_SCRIPTS="../simbricks-gem5/packer/install-m5.sh"
EXTRA_SCRIPTS ?=

# Install the debug kernel so gem5's ELF boot/vmlinux is produced. On by
# default; set false for QEMU-only images (skips the large -dbg package).
INSTALL_VMLINUX ?= true

# Extract the kernel config + linux-headers build tree to output-base/ for
# building out-of-tree modules on the host. Off by default; turning it on also
# installs the headers into the image (which enlarges it).
EXTRACT_HEADERS ?= false

# turn a make list into the HCL list literal packer wants
comma := ,
empty :=
space := $(empty) $(empty)
hcl_list = [$(subst $(space),$(comma),$(patsubst %,"%",$(1)))]

VARS = \
  -var source_image=$(SOURCE_IMAGE) \
  -var source_checksum=$(SOURCE_CHECKSUM) \
  -var accelerator=$(ACCELERATOR) \
  -var install_vmlinux=$(INSTALL_VMLINUX) \
  -var extract_headers=$(EXTRACT_HEADERS) \
  -var name=base -var output=output-base \
  -var 'scripts=$(call hcl_list,$(BASE_SCRIPTS) $(EXTRA_SCRIPTS))'

.PHONY: image validate init clean

# cloud image -> image (init -> validate -> build). Validating first catches
# HCL/variable mistakes before packer downloads an image and boots a VM.
image: validate
	$(PACKER) build $(VARS) image.pkr.hcl

# validate the config/vars without building anything
validate: init
	$(PACKER) validate $(VARS) image.pkr.hcl

init:
	$(PACKER) init image.pkr.hcl

clean:
	rm -rf output-* packer_cache
