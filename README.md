# SimBricks image harness

A tiny, simulator-independent way to **generate** the Linux disk image and boot
artifacts SimBricks needs. One disk image plus its boot files fall out.

By default no kernel is compiled: the kernel is the distro's own, and the ELF
`vmlinux` a simulator like gem5 needs is just its debug-kernel package, extracted.
There is also an optional path that builds a custom no-initrd kernel (which boots
under gem5) — see [custom no-initrd kernel](#custom-no-initrd-kernel).

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
- `tar` (boot artifacts are staged in the guest and downloaded over SSH — no
  libguestfs/kernel packages needed on the host).

## Dev container

`.devcontainer/` builds an image with all of the above (stock qemu, packer,
make/git) via [.devcontainer/Dockerfile](.devcontainer/Dockerfile), so you can
build without touching the host. Open the repo in VS Code and "Reopen in
Container".

It passes the host's `/dev/kvm` through for accelerated builds. If your host has
no KVM, remove the `--device=/dev/kvm` runArg from
[.devcontainer/devcontainer.json](.devcontainer/devcontainer.json) and build with
`-var accelerator=tcg` (or `make image ACCELERATOR=tcg`).

### Headless (no VS Code)

Use the same image as a plain container — build it once, then run a build:

```sh
docker build -t simbricks-image-harness .devcontainer
docker run --rm -it --device /dev/kvm \
  --group-add "$(getent group kvm | cut -d: -f3)" \
  -v "$PWD:/work" -w /work simbricks-image-harness \
  make image SOURCE_IMAGE=... SOURCE_CHECKSUM=...
```

Output lands in `./output-base`. `INPUT=<dir>` must be inside `$PWD`. No KVM: drop
`--device`/`--group-add` and add `ACCELERATOR=tcg`.

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
  -var 'base_scripts=["scripts/install-boot-artifacts.sh","scripts/install-base.sh","scripts/configure-boot.sh","scripts/install-guestinit.sh"]' \
  image.pkr.hcl
```

On CI without nested virtualization, add `-var accelerator=tcg` (slower). The
gem5 ELF `vmlinux` is produced by default (`install_vmlinux=true`); set
`-var install_vmlinux=false` for QEMU-only images to skip the vmlinux step. The
qcow2 is converted to `<output>/<name>.raw` by default (`convert_raw=true`); set
`-var convert_raw=false` (`make image CONVERT_RAW=false`) to keep only the qcow2.

## How components plug in

The template runs two ordered lists of opaque shell scripts in the guest — the
base stages (`base_scripts`), then the components (`scripts`) — and finishes with
`scripts/cleanup.sh`. The base stages are `install-boot-artifacts.sh` (install
the generic kernel and decompress its `vmlinux`), `install-base.sh` (your
software), `configure-boot.sh` (trim the GRUB delay), `install-guestinit.sh` (the
SimBricks payload runner); a component (gem5, Corundum, ...) ships its own
install script and goes in the second list:

```sh
packer build \
  -var name=base -var output=output-base \
  -var 'base_scripts=["scripts/install-boot-artifacts.sh",
                      "scripts/install-base.sh",
                      "scripts/configure-boot.sh",
                      "scripts/install-guestinit.sh"]' \
  -var 'scripts=["path/to/another/install/script.sh"]' \
  image.pkr.hcl
```

Between the two lists the guest reboots, onto the kernel
`install-boot-artifacts.sh` (or `kernel/install-kernel.sh`) just installed. So a
component sees that kernel as `uname -r` and can build *and* load out-of-tree
modules against it — without the reboot the build VM still runs the source
image's kernel and only the on-disk `/lib/modules` has changed. Skip it with
`-var reboot_between=false` (`make image REBOOT=false`).

The ELF `vmlinux` the kernel stage decompresses is staged by
`scripts/stage-boot-artifacts.sh` and downloaded from the guest over SSH
(controlled by `-var install_vmlinux=`, default true). When you build a
specialization on top of a prebuilt base image, clear `base_scripts`
(`install-boot-artifacts.sh` included) — the kernel and its `vmlinux` are already
in the base, so there is nothing to redo, and nothing to reboot onto.

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

Base + all component scripts in a single build, with the reboot in between. With
the Makefile, append component scripts via `EXTRA_SCRIPTS`:
`make image EXTRA_SCRIPTS="path/to/another/install/script.sh"`.

### layered (reuse a base)

Build the base once, then build several specializations on top of it without
redoing the base stages (generic kernel, packages, ...). Point `SOURCE_IMAGE` at
the base image a previous run produced and clear `BASE_SCRIPTS` so only your
component runs:

```sh
make image                                   # 1. build the base once -> output-base/base

make image NAME=you-nre-image-name \                   # 2. specialize on top of it
  SOURCE_IMAGE=output/base/base SOURCE_CHECKSUM=none \
  BASE_SCRIPTS= EXTRA_SCRIPTS="path/to/your/specific/install/script.sh"
```

The base keeps the generic kernel + its `vmlinux` through cleanup, so the
specialization reuses them and just extracts its own `boot/` artifacts. It also
boots that kernel from the start, so components build against it with no reboot
needed. `SOURCE_CHECKSUM=none` is needed because the default checksum is for the
cloud image, not your local base.

### Custom no-initrd kernel

Some simulators (gem5's current fork) boot a `vmlinux` directly with no initrd, where
the distro's modular kernel never reaches userspace (see the caveat under
[gem5](#gem5)). `kernel/` builds one that does — root fs, disk and serial console
built in — outside packer, and it boots under gem5:

```sh
make kernel                         # -> output/kernel/{vmlinux,linux-*.deb}
make image NAME=gem5 INPUT=output/kernel \
  BASE_SCRIPTS="kernel/install-kernel.sh scripts/install-base.sh scripts/configure-boot.sh scripts/install-guestinit.sh" \
  EXTRA_SCRIPTS="examples/gem5/install-m5.sh"
```

`kernel/install-kernel.sh` replaces `install-boot-artifacts.sh`: it installs the
built kernel handed in via `INPUT` (`/tmp/input`) instead of the generic one.
Version, config and the gem5 timer patch live in `kernel/build-kernel.sh`.
Because it is a base stage, the reboot puts the guest on that kernel before the
component scripts run, so out-of-tree drivers (the Corundum `mqnic` stage above)
build and load against it under `/lib/modules/<ver>/build`.

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
> an initrd — build one with `make kernel` (see
> [custom no-initrd kernel](#custom-no-initrd-kernel)).


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
scripts/stage-boot-artifacts.sh harness-owned (guest): tar vmlinuz/initrd/vmlinux for SSH download
scripts/cleanup.sh          sanitize + shrink (runs last)
kernel/                     optional: build + install a custom no-initrd kernel (boots under gem5; + timer patch)
examples/gem5/install-m5.sh optional: install the gem5 m5 guest tool
examples/corundum/          optional: build the Corundum mqnic driver against it
Makefile                    convenience wrappers
```
