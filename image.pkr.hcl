# SimBricks image harness — a packer template that turns a cloud image into a
# base image. Guest actions are opaque scripts (var.scripts). Output contract:
#   <output>/<name>.raw     raw disk image
#   <output>/boot/vmlinuz   distro kernel, bzImage
#   <output>/boot/initrd    distro initramfs
#   <output>/boot/vmlinux   distro kernel, uncompressed ELF (if install_vmlinux)
# Kernel plumbing: scripts/{install,extract}-boot-artifacts.sh.

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
  description = "Guest provisioning scripts, run in order. Components plug in here."
}

variable "input" {
  type        = string
  default     = ""
  description = "Optional local tarball, unpacked to /tmp/input in the guest before the scripts run. `make image INPUT=<dir>` tars a directory for you. Empty = none."
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
  default = "kvm" # "tcg" on CI without nested virt
}

variable "ssh_username"{
  type = string
  default = "ubuntu"
}

variable "ssh_password"{
  type = string
  default = "ubuntu"
}

# Decompress boot/vmlinux (uncompressed kernel ELF) from the kernel image; false to skip.
variable "install_vmlinux" {
  type = bool
  default = true
}

# Convert the built qcow2 to raw (<output>/<name>.raw); false keeps only the qcow2.
variable "convert_raw" {
  type = bool
  default = false
}

# Forwarded into the guest provisioners; default off the host env, empty = none.
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
  # Run each provisioner script as root, forwarding any proxy.
  execute_command = "chmod +x {{.Path}}; sudo -E env {{.Vars}} http_proxy=${var.http_proxy} https_proxy=${var.https_proxy} {{.Path}}"
}

source "qemu" "image" {
  iso_url          = var.source_image
  iso_checksum     = var.source_checksum
  disk_image       = true
  disk_size        = var.disk_size
  format           = "qcow2"
  accelerator      = var.accelerator
  qemu_binary      = var.qemu_binary
  memory           = var.memory
  cpus             = var.cpus
  headless         = true
  net_device       = "virtio-net"
  disk_interface   = "virtio"

  # cloud-init NoCloud seed over packer's HTTP server (via SMBIOS serial), so no
  # CD image and no xorriso/mkisofs on the host.
  http_directory   = "http"
  qemuargs         = [
    ["-smbios", "type=1,serial=ds=nocloud;instance-id=packer;seedfrom=http://{{ .HTTPIP }}:{{ .HTTPPort }}/"],
    ["-serial", "file:/tmp/qemu-serial.log"], # diagnostic: guest console -> file
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

  # 0. optional: upload + unpack a local input tarball to /tmp/input. `make image
  #    INPUT=<dir>` tars the dir first (packer can't: the file source is checked
  #    before any provisioner runs). Via a tarball so symlinks aren't followed.
  dynamic "provisioner" {
    for_each = var.input == "" ? [] : [var.input]
    labels   = ["file"]
    content {
      source      = provisioner.value
      destination = "/tmp/input.tar.gz"
    }
  }
  dynamic "provisioner" {
    for_each = var.input == "" ? [] : [var.input]
    labels   = ["shell"]
    content {
      inline = ["mkdir -p /tmp/input", "tar xzf /tmp/input.tar.gz -C /tmp/input"]
    }
  }

  # 1. base + component scripts, in order. install-boot-artifacts.sh is the first
  #    base script, so it runs before components (they build against the generic
  #    kernel it installs) and can be skipped like any base stage when reusing a
  #    prebuilt base image (drop it from var.scripts / clear BASE_SCRIPTS).
  provisioner "shell" {
    scripts          = var.scripts
    execute_command  = local.execute_command
    environment_vars = [
      "WITH_VMLINUX=${var.install_vmlinux}",
    ]
  }

  # 2. sanitize + shrink, last
  provisioner "shell" {
    script          = "scripts/cleanup.sh"
    execute_command = local.execute_command
  }

  # 3. optionally convert to raw, then extract boot artifacts (from the raw if made,
  #    else straight from the qcow2 — libguestfs reads either).
  post-processor "shell-local" {
    inline = var.convert_raw ? [
      "qemu-img convert -f qcow2 -O raw -S 4k ${var.output}/${var.name} ${var.output}/${var.name}.raw",
      "WITH_VMLINUX=${var.install_vmlinux} sh ./scripts/extract-boot-artifacts.sh ${var.output}/${var.name}.raw ${var.output}"
    ] : [
      "WITH_VMLINUX=${var.install_vmlinux} sh ./scripts/extract-boot-artifacts.sh ${var.output}/${var.name} ${var.output}"
    ]
  }
}
