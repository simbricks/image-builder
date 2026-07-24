# SimBricks image harness

A tiny, simulator-independent way to **generate** the Linux disk image and boot
artifacts SimBricks needs. One disk image plus its boot files fall out.

By default no kernel is compiled: the kernel is the distro's own, and the ELF
`vmlinux` e.g. gem5 needs is just its debug-kernel package, extracted. gem5 boots
without an initrd, so it has an optional path that builds a custom no-initrd
kernel instead — see [gem5: custom no-initrd kernel](#gem5-custom-no-initrd-kernel).

## What it produces

```
output-base/
  base.raw          # the disk image (raw; every simulator reads it)
  boot/
    vmlinuz         # distro kernel, bzImage   -> QEMU  -kernel   (optional)
    initrd          # distro initramfs         -> QEMU  -initrd / future gem5
    vmlinux         # distro kernel, ELF        -> gem5  --kernel  (if install_vmlinux)
```

`base.raw` is the single artifact. `boot/*` are extracted copies of files that
live *inside* that image, provided pre-extracted so simulators can be handed a
kernel/initrd on the command line (e.g. to override the kernel cmdline per run)
without needing virt-tools at simulation time.

## Requirements (host)

- `packer` (with the qemu plugin; `make init` installs it)
- a stock `qemu-system-x86_64` and `qemu-img`. KVM recommended.
- `libguestfs-tools` (Debian/Ubuntu) or `guestfs-tools` (Fedora) for
  `virt-copy-out` / `virt-ls`.

## Dev container

`.devcontainer/` builds an image with all of the above (stock qemu, libguestfs,
packer, make/git) via [.devcontainer/Dockerfile](.devcontainer/Dockerfile), so
you can build without touching the host. Open the repo in VS Code and "Reopen in
Container".

It passes the host's `/dev/kvm` through for accelerated builds. If your host has
no KVM, remove the `--device=/dev/kvm` runArg from
[.devcontainer/devcontainer.json](.devcontainer/devcontainer.json) and build with
`-var accelerator=tcg` (or `make image ACCELERATOR=tcg`).

## Build

Via the Makefile:

```sh
make image SOURCE_IMAGE=https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2 \
          SOURCE_CHECKSUM=file:https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS
```

Or packer directly:

```sh
packer init image.pkr.hcl
packer build \
  -var source_image=https://.../debian-13-genericcloud-amd64.qcow2 \
  -var source_checksum=file:https://.../SHA512SUMS \
  -var name=base -var output=output-base \
  -var 'scripts=["scripts/install-boot-artifacts.sh","scripts/install-base.sh","scripts/configure-boot.sh","scripts/install-guestinit.sh"]' \
  image.pkr.hcl
```

On CI without nested virtualization, add `-var accelerator=tcg` (slower). The
gem5 ELF `vmlinux` is produced by default (`install_vmlinux=true`); set
`-var install_vmlinux=false` for QEMU-only images to skip the vmlinux step.

## How components plug in

The template runs an ordered list of opaque shell `scripts` in the guest, then
runs `scripts/cleanup.sh`. The base stages — `install-boot-artifacts.sh` (install
the generic kernel and decompress its `vmlinux`), `install-base.sh` (your
software), `configure-boot.sh` (trim the GRUB delay), `install-guestinit.sh` (the
SimBricks payload runner) — are just the first entries; a component (gem5,
Corundum, ...) ships its own install script and you append it:

```sh
packer build \
  -var name=base -var output=output-base \
  -var 'scripts=["scripts/install-boot-artifacts.sh",
                 "scripts/install-base.sh",
                 "scripts/configure-boot.sh",
                 "scripts/install-guestinit.sh",
                 "path/to/another/install/script.sh"]' \
  image.pkr.hcl
```

`install-boot-artifacts.sh` runs first so components build against the generic
kernel it installs; the ELF `vmlinux` it decompresses is copied out on the host by
`scripts/extract-boot-artifacts.sh` (controlled by `-var install_vmlinux=`, default
true). When you build a specialization on top of a prebuilt base image, drop the
base scripts (`install-boot-artifacts.sh` included) from the list — the kernel and
its `vmlinux` are already in the base, so there is nothing to redo.

Because cleanup runs last, component scripts can pull in `build-essential`,
`linux-headers-*`, etc.; cleanup removes them afterward.

### Getting build input to a script

A component script usually **fetches its own input** — `git clone` a pinned ref,
`curl` a release — from inside the guest (the VM has network, and the
`http_proxy`/`https_proxy` vars are forwarded). That is the recommended way and
keeps builds reproducible when you pin the ref.

For local, unpublished input (a working tree, patches, prebuilt blobs), upload it
instead: `make image INPUT=<dir>` tars the directory and unpacks it to
`/tmp/input` in the guest before the scripts run, where your script reads it.
With plain packer, pass a tarball via `-var input=<file.tar.gz>` (packer can't
tar it for you — the file source is checked before any provisioner runs).

### one-shot

List base + all component scripts in a single build. With the
Makefile, append component scripts via `EXTRA_SCRIPTS`:
`make image EXTRA_SCRIPTS="path/to/another/install/script.sh"`.

### layered (reuse a base)

Build the base once, then build several specializations on top of it without
redoing the base stages (generic kernel, packages, ...). Point `SOURCE_IMAGE` at
the base image a previous run produced and clear `BASE_SCRIPTS` so only your
component runs:

```sh
make image                                   # 1. build the base once -> output-base/base

make image NAME=you-nre-image-name \                   # 2. specialize on top of it
  SOURCE_IMAGE=output-base/base SOURCE_CHECKSUM=none \
  BASE_SCRIPTS= EXTRA_SCRIPTS="path/to/your/specific/install/script.sh"
```

The base keeps the generic kernel + its `vmlinux` through cleanup, so the
specialization reuses them and just extracts its own `boot/` artifacts.
`SOURCE_CHECKSUM=none` is needed because the default checksum is for the cloud
image, not your local base.

### gem5: custom no-initrd kernel

gem5's current fork boots a `vmlinux` with no initrd, so the distro's modular
kernel won't reach userspace (see the caveat under [gem5](#gem5)). `examples/gem5/`
builds one that does — root fs, disk and serial console built in — outside packer:

```sh
make gem5-kernel                         # -> output/gem5-kernel/{vmlinux,linux-*.deb}
make image NAME=gem5 INPUT=output/gem5-kernel \
  BASE_SCRIPTS="examples/gem5/install-gem5-kernel.sh scripts/install-base.sh scripts/configure-boot.sh scripts/install-guestinit.sh" \
  EXTRA_SCRIPTS="examples/corundum/install-mqnic.sh"
```

`install-gem5-kernel.sh` replaces `install-boot-artifacts.sh`: it installs the
built kernel handed in via `INPUT` (`/tmp/input`) instead of the generic one.
Version and config live in `examples/gem5/build-gem5-kernel.sh`. Out-of-tree
drivers (the Corundum `mqnic` stage above) then build against it under
`/lib/modules/<ver>/build`.

## Using the output with the simulators

### QEMU

Boots the disk directly through GRUB — nothing extra needed. To override the
kernel command line per run, use the extracted kernel/initrd:

```
-drive file=output-base/base.raw,format=raw ...
# or, for cmdline control:
-kernel output-base/boot/vmlinuz -initrd output-base/boot/initrd \
  -append "console=ttyS0 root=/dev/sda1 rw <your extra args>" ...
```

### gem5

```
gem5.opt configs/simbricks/simbricks.py \
    --kernel=output-base/boot/vmlinux \
    --disk-image=output-base/base.raw \
    --command-line="console=ttyS0 root=/dev/sda1 rw nokaslr" \
    --simbricks-pci=<sock> --simbricks-eth=<sock>
```

Once your gem5 fork supports x86 initrd, add:

```
    --initrd=output-base/boot/initrd
```

> **Boot-to-userspace caveat (gem5, current fork).** This is a *simulator*
> limitation, independent of image building. Distro kernels are modular
> (ext4/virtio as `.ko`, loaded from the initrd), and the current SimBricks
> gem5 fork does not load an initrd on x86, so a distro `vmlinux` will not reach
> userspace on it. That gap closes when the fork gains x86 initrd support (via a
> gem5 upgrade or a workload patch); the harness output does not change — you
> just add `--initrd`. Until then, gem5 needs a kernel that mounts root without
> an initrd — build one with `make gem5-kernel` (see
> [gem5: custom no-initrd kernel](#gem5-custom-no-initrd-kernel)).


## Guest payload protocol

`install-guestinit.sh` installs `/home/ubuntu/guestinit.sh`, unchanged from the
old SimBricks flow: orchestration attaches the per-experiment payload as a second
disk (`/dev/sdb`); the guest untars it and runs `guest/run.sh`.

## Files

```
image.pkr.hcl               the single template
http/{user-data,meta-data}  cloud-init NoCloud seed
scripts/install-boot-artifacts.sh base stage (guest): install the generic kernel + decompress its vmlinux
scripts/install-base.sh     base stage: the packages you want in the image
scripts/configure-boot.sh   base stage: trim the GRUB menu delay for fast boots
scripts/install-guestinit.sh base stage: SimBricks guest payload runner (/dev/sdb -> guest/run.sh)
scripts/extract-boot-artifacts.sh harness-owned (host): copy vmlinuz/initrd/vmlinux out
scripts/cleanup.sh          sanitize + shrink (runs last)
examples/gem5/              optional: build (build-gem5-kernel.sh) + install a custom no-initrd kernel
examples/corundum/          optional: build the Corundum mqnic driver against it
Makefile                    convenience wrappers
```
