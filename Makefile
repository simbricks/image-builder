# Wrappers around `packer build` (optional — see README). Override any VAR:
#   make image SOURCE_IMAGE=... SOURCE_CHECKSUM=...

PACKER        ?= packer
SOURCE_IMAGE  ?= https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img
SOURCE_CHECKSUM ?= file:https://cloud-images.ubuntu.com/minimal/releases/jammy/release/SHA256SUMS 
ACCELERATOR   ?= kvm

# Image name (disk filename stem). Override to chain specializations off a prebuilt
# base: build once with NAME=base, then reuse it as SOURCE_IMAGE.
NAME          ?= base
# Top-level output dir; the kernel and each image get their own subfolder under it.
OUTPUT_DIR    ?= output
OUTPUT        ?= $(OUTPUT_DIR)/$(NAME)

# Base stages, then extra component scripts, run in order. install-boot-artifacts.sh
# (generic kernel + vmlinux) comes first; clear BASE_SCRIPTS to reuse a base image.
BASE_SCRIPTS  ?= scripts/install-boot-artifacts.sh scripts/install-base.sh scripts/configure-boot.sh scripts/install-guestinit.sh
EXTRA_SCRIPTS ?=

# Local dir made available at /tmp/input in the guest, tarred for upload (empty = off).
INPUT ?=
INPUT_TAR := $(and $(INPUT),/tmp/simbricks-image-input.tar.gz)

# boot/vmlinux (uncompressed kernel ELF, decompressed from the image); false to skip.
INSTALL_VMLINUX ?= true

# make list -> HCL list literal
comma := ,
empty :=
space := $(empty) $(empty)
hcl_list = [$(subst $(space),$(comma),$(patsubst %,"%",$(1)))]

VARS = \
  -var source_image=$(SOURCE_IMAGE) \
  -var source_checksum=$(SOURCE_CHECKSUM) \
  -var accelerator=$(ACCELERATOR) \
  -var install_vmlinux=$(INSTALL_VMLINUX) \
  -var input=$(INPUT_TAR) \
  -var name=$(NAME) -var output=$(OUTPUT) \
  -var 'scripts=$(call hcl_list,$(BASE_SCRIPTS) $(EXTRA_SCRIPTS))'

.PHONY: image validate init clean pack-input kernel

# tar INPUT (if set) so the file provisioner's source exists before packer runs
pack-input:
	$(if $(INPUT),tar czf $(INPUT_TAR) -C $(INPUT) .)

# init -> validate -> build (packer writes the image into $(OUTPUT_DIR)/$(NAME))
image: validate
	mkdir -p $(OUTPUT_DIR)
	$(PACKER) build $(VARS) image.pkr.hcl

validate: init pack-input
	$(PACKER) validate $(VARS) image.pkr.hcl

init:
	$(PACKER) init image.pkr.hcl

# `make kernel`: build linux kernel (pinned 5.15.93) outside packer into
# $(KERNEL_OUT); feed it to an image build with INPUT=$(KERNEL_OUT) + kernel/install-kernel.sh.
KERNEL_OUT ?= $(OUTPUT_DIR)/kernel

kernel:
	mkdir -p $(OUTPUT_DIR)
	OUT=$(KERNEL_OUT) ./kernel/build-kernel.sh

clean:
	rm -rf $(OUTPUT_DIR) packer_cache
