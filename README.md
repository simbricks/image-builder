# SimBricks image harness

A tiny, simulator-independent way to **generate** the Linux disk image and boot
artifacts SimBricks needs. One disk image plus its boot files fall out.

No kernel is compiled anywhere. The kernel is the distro's own; the ELF
`vmlinux` e.g. gem5 needs is just the distro's debug-kernel package, extracted.

## What it produces

```
output-base/
  base.raw          # the disk image (raw; every simulator reads it)
  boot/
    vmlinuz         # distro kernel, bzImage   -> QEMU  -kernel   (optional)
    initrd          # distro initramfs         -> QEMU  -initrd / future gem5
    vmlinux         # distro kernel, ELF        -> gem5  --kernel  (if -dbg pkg present)
```

`base.raw` is the single artifact. `boot/*` are extracted copies of files that
live *inside* that image, provided pre-extracted so simulators can be handed a
kernel/initrd on the command line (e.g. to override the kernel cmdline per run)
without needing virt-tools at simulation time.

With `-var extract_headers=true` (`make image EXTRACT_HEADERS=true`) kernel config
and headers are extracted as well, for building out-of-tree modules on the
host (normally components build their modules in packer instead; see below):

```
output-base/
  boot/config       # kernel .config
  headers/          # linux-headers build tree
```

## Requirements (host)

- `packer` (with the qemu plugin; `make init` installs it)
- a stock `qemu-system-x86_64` and `qemu-img`. KVM recommended.
- `libguestfs-tools` (Debian/Ubuntu) or `guestfs-tools` (Fedora) for
  `virt-copy-out` / `virt-ls`.

## Dev container

`.devcontainer/` installs all of the above (stock qemu, libguestfs, packer,
make/git) into a prebuilt base image via
[.devcontainer/setup.sh](.devcontainer/setup.sh), so you can build without
touching the host. Open the repo in VS Code and "Reopen in Container".

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
  -var 'scripts=["scripts/install-base.sh","scripts/configure-boot.sh","scripts/install-guestinit.sh"]' \
  image.pkr.hcl
```

On CI without nested virtualization, add `-var accelerator=tcg` (slower). The
gem5 ELF `vmlinux` is produced by default (`install_vmlinux=true`); set
`-var install_vmlinux=false` for QEMU-only images to skip the large `-dbg`
package.

## How components plug in

The template runs an ordered list of opaque shell `scripts` in the guest, then
runs the harness-owned kernel/boot plumbing and `scripts/cleanup.sh`. The base
stages (`install-base.sh` = your software, `configure-boot.sh` = trim the GRUB
delay, `install-guestinit.sh` = the SimBricks payload runner) are just the first
entries; a component (gem5, Corundum, ...) ships its own install script and you
append it:

```sh
packer build \
  -var name=base -var output=output-base \
  -var 'scripts=["scripts/install-base.sh",
                 "scripts/configure-boot.sh",
                 "scripts/install-guestinit.sh",
                 "path/to/another/install/script.sh",
                 "path/to/yet/one/additional/install/script.sh"]' \
  image.pkr.hcl
```

The ELF `vmlinux` and the optional headers/config extraction are not stages,
they are harness-owned plumbing (`scripts/install-boot-artifacts.sh` in the
guest, `scripts/extract-boot-artifacts.sh` on the host), controlled by
`-var install_vmlinux=` (default true) and `-var extract_headers=` (default
false).

Because cleanup runs last, those scripts can pull in `build-essential`,
`linux-headers-$(uname -r)`, etc.; cleanup removes them afterward. Any step that
changes the kernel must run *before* driver builds.

### one-shot

List base + all component scripts in a single build. With the
Makefile, append component scripts via `EXTRA_SCRIPTS`:
`make image EXTRA_SCRIPTS="path/to/another/install/script.sh"`.

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
> an initrd; how you obtain that is a gem5-side concern, not the harness's.


## Guest payload protocol

`install-guestinit.sh` installs `/home/ubuntu/guestinit.sh`, unchanged from the
old SimBricks flow: orchestration attaches the per-experiment payload as a second
disk (`/dev/sdb`); the guest untars it and runs `guest/run.sh`.

## Files

```
image.pkr.hcl               the single template
http/{user-data,meta-data}  cloud-init NoCloud seed
scripts/install-base.sh     the packages you want in the image
scripts/configure-boot.sh   trim the GRUB menu delay for fast simulator boots
scripts/install-guestinit.sh SimBricks guest payload runner (/dev/sdb -> guest/run.sh)
scripts/cleanup.sh          sanitize + shrink (runs last)
scripts/install-boot-artifacts.sh harness-owned (guest): install the -dbg kernel + headers
scripts/extract-boot-artifacts.sh harness-owned (host): copy vmlinuz/initrd/vmlinux/config/headers out
Makefile                    convenience wrappers
```
