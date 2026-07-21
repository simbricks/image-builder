# SimBricks image harness — single packer template.
#
# Used for both build stages with the same file:
#   1. cloud image  -> base image           (scripts install the base + guest tools)
#   2. base image   -> extended image        (scripts install one component's bits)
#
# The harness itself knows nothing about SimBricks, gem5, m5 or Corundum. Every
# guest-side action is an opaque shell script passed via `scripts`. The only
# thing the harness guarantees is the output contract:
#
#   <output>/<name>.raw          the disk image (raw; every simulator reads it)
#   <output>/boot/vmlinuz        distro kernel (bzImage) — for QEMU -kernel path
#   <output>/boot/initrd         distro initramfs        — for QEMU / future gem5
#   <output>/boot/vmlinux        distro kernel (ELF)      — for gem5 --kernel
#
# vmlinux is only produced when install_vmlinux=true (the default) installs a
# matching linux-image-*-dbg package in the guest. This kernel/boot artifact
# plumbing lives in scripts/install-boot-artifacts.sh (guest) and
# scripts/extract-boot-artifacts.sh (host).
#
# With -var extract_headers=true, additionally (opt-in, for building out-of-tree
# modules on the host):
#   <output>/boot/config         kernel .config
#   <output>/headers/            linux-headers build tree

packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1.1"
    }
  }
}

# ---- Inputs -----------------------------------------------------------------

variable "source_image" {
  type        = string
  description = "URL or local path of the source qcow2/raw (cloud image, or a base image built by a previous run)."
}

variable "source_checksum" {
  type        = string
  default     = "none"
  description = "Checksum for source_image, e.g. 'sha256:...' or 'file:https://.../SHA512SUMS'. Use 'none' for local files."
}

variable "name" {
  type        = string
  default     = "base"
  description = "Image name; also the disk filename stem."
}

variable "output" {
  type        = string
  default     = "output-base"
  description = "Output directory."
}

variable "scripts" {
  type        = list(string)
  default     = []
  description = "Guest provisioning scripts, run in order. Components (gem5 m5, corundum mqnic, ...) plug in here."
}

variable "disk_size"   { 
  type = string
  default = "8G"
}

variable "memory"      {
  type = number
  default = 2048
}

variable "cpus"        {
  type = number
  default = 2
}

variable "qemu_binary" {
  type = string
  default = "qemu-system-x86_64"
}

variable "accelerator" {
  type = string
  default = "kvm" # set to "tcg" on CI without nested virt
}

variable "ssh_username"{
  type = string
  default = "ubuntu"
}

variable "ssh_password"{
  type = string
  default = "ubuntu"
}

# Install the debug kernel so gem5's ELF vmlinux (boot/vmlinux) is produced.
# On by default; set false for QEMU-only images (skips the large -dbg package).
variable "install_vmlinux" {
  type = bool
  default = true
}

# Also install the linux-headers tree in the image and extract it + the kernel
# config to <output>/, for building out-of-tree modules on the host. Off by
# default; enlarges the image.
variable "extract_headers" {
  type = bool
  default = false
}

# Forwarded into the guest provisioners so apt/curl work behind a proxy.
# Default to the host's environment; empty means "no proxy".
variable "http_proxy" {
  type = string
  default = env("http_proxy")
}

variable "https_proxy" {
  type = string
  default = env("https_proxy")
}

# ---- Builder ----------------------------------------------------------------

locals {
  # Run each provisioner script as root, forwarding any configured proxy.
  execute_command = "chmod +x {{.Path}}; sudo -E env {{.Vars}} http_proxy=${var.http_proxy} https_proxy=${var.https_proxy} {{.Path}}"
}

source "qemu" "image" {
  iso_url          = var.source_image
  iso_checksum     = var.source_checksum
  disk_image       = true            # source is a disk image, not an install ISO
  disk_size        = var.disk_size
  format           = "qcow2"
  accelerator      = var.accelerator
  qemu_binary      = var.qemu_binary
  memory           = var.memory
  cpus             = var.cpus
  headless         = true
  net_device       = "virtio-net"
  disk_interface   = "virtio"

  # cloud-init NoCloud seed served over packer's built-in HTTP server; the guest
  # is pointed at it via the SMBIOS system serial. No CD image is built, so the
  # host needs no xorriso/mkisofs. (This is the long-standing SimBricks method.)
  http_directory   = "http"
  qemuargs         = [
    ["-smbios", "type=1,serial=ds=nocloud;instance-id=packer;seedfrom=http://{{ .HTTPIP }}:{{ .HTTPPort }}/"],
  ]

  ssh_username     = var.ssh_username
  ssh_password     = var.ssh_password
  ssh_timeout      = "10m"

  shutdown_command = "sudo shutdown -P now"
  output_directory = var.output
  vm_name          = var.name
}

# ---- Build ------------------------------------------------------------------

build {
  sources = ["source.qemu.image"]

  # 1. component / base provisioning (opaque scripts, run in the given order)
  provisioner "shell" {
    scripts         = var.scripts
    execute_command = local.execute_command
  }

  # 2. harness-owned kernel/boot artifacts: install the -dbg kernel (gem5's ELF
  #    vmlinux) and, when extracting headers, the linux-headers tree. Flags come
  #    from the environment.
  provisioner "shell" {
    script           = "scripts/install-boot-artifacts.sh"
    execute_command  = local.execute_command
    environment_vars = [
      "WITH_VMLINUX=${var.install_vmlinux}",
      "WITH_HEADERS=${var.extract_headers}",
    ]
  }

  # 3. always sanitize + shrink last, after everything above has built
  provisioner "shell" {
    script          = "scripts/cleanup.sh"
    execute_command = local.execute_command
  }

  # 4. convert to raw and extract the boot artifacts out of the finished image
  post-processor "shell-local" {
    inline = [
      "qemu-img convert -f qcow2 -O raw -S 4k ${var.output}/${var.name} ${var.output}/${var.name}.raw",
      "WITH_HEADERS=${var.extract_headers} sh ./scripts/extract-boot-artifacts.sh ${var.output}/${var.name}.raw ${var.output}"
    ]
  }
}
