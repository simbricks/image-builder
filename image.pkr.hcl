# SimBricks image harness — a packer template that turns a cloud image into a
# base image. Guest actions are opaque scripts (var.base_scripts, var.scripts,
# with a reboot between them). Output contract:
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

variable "base_scripts" {
  type        = list(string)
  default     = []
  description = "Harness base stages (kernel, packages, boot config), run in order before the reboot."
}

variable "scripts" {
  type        = list(string)
  default     = []
  description = "Guest provisioning scripts, run in order after base_scripts. Components plug in here."
}

variable "reboot_between" {
  type        = bool
  default     = true
  description = "Reboot the guest between base_scripts and scripts, so components build and load modules against the kernel the base stages installed. Set false to skip."
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

variable "compressed" {
  type = bool
  default = true
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
  disk_compression = var.compressed

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

  # 1. base stages, in order; install-boot-artifacts.sh installs the kernel.
  #    Empty when a layered build reuses a prebuilt base, and an empty script
  #    list fails validation -- hence dynamic, here and below.
  dynamic "provisioner" {
    for_each = length(var.base_scripts) == 0 ? [] : [1]
    labels   = ["shell"]
    content {
      scripts          = var.base_scripts
      execute_command  = local.execute_command
      environment_vars = [
        "WITH_VMLINUX=${var.install_vmlinux}",
      ]
    }
  }

  # 2. reboot onto that kernel.
  dynamic "provisioner" {
    for_each = var.reboot_between && length(var.base_scripts) > 0 ? [1] : []
    labels   = ["shell"]
    content {
      inline            = ["sudo reboot"]
      expect_disconnect = true
      skip_clean        = true
    }
  }

  # 3. component scripts, in order, now running on it.
  dynamic "provisioner" {
    for_each = length(var.scripts) == 0 ? [] : [1]
    labels   = ["shell"]
    content {
      scripts          = var.scripts
      execute_command  = local.execute_command
      pause_before     = var.reboot_between && length(var.base_scripts) > 0 ? "3s" : "0s"
      environment_vars = [
        "WITH_VMLINUX=${var.install_vmlinux}",
      ]
    }
  }

  # 4. stage boot artifacts (vmlinuz/initrd/vmlinux) into a tarball in the guest,
  #    then download it over SSH — replaces libguestfs, so the host needs no kernel
  #    or appliance packages. Runs before cleanup (which wipes /tmp).
  provisioner "shell" {
    script           = "scripts/stage-boot-artifacts.sh"
    execute_command  = local.execute_command
    environment_vars = [
      "WITH_VMLINUX=${var.install_vmlinux}",
    ]
  }
  provisioner "file" {
    direction   = "download"
    source      = "/tmp/boot-artifacts.tar.gz"
    destination = "${var.output}/boot-artifacts.tar.gz"
  }

  # 5. sanitize + shrink, last
  provisioner "shell" {
    script          = "scripts/cleanup.sh"
    execute_command = local.execute_command
  }

  # 6. unpack the downloaded artifacts into <output>/boot (optionally converting the
  #    qcow2 to raw first). Only qemu-img + tar on the host — no kernel packages.
  post-processor "shell-local" {
    inline = concat(
      var.convert_raw ? ["qemu-img convert -f qcow2 -O raw -S 4k ${var.output}/${var.name} ${var.output}/${var.name}.raw"] : [],
      [
        "mkdir -p ${var.output}/boot",
        "tar xzf ${var.output}/boot-artifacts.tar.gz -C ${var.output}/boot",
        "rm -f ${var.output}/boot-artifacts.tar.gz",
      ]
    )
  }
}
