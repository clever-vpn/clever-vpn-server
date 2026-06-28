packer {
  required_plugins {
    digitalocean = {
      version = ">= 1.1.1"
      source  = "github.com/digitalocean/digitalocean"
    }
  }
}

variable "do_token" {
  type        = string
  description = "DigitalOcean API token"
  sensitive   = true
}

variable "version" {
  type        = string
  description = "clever-vpn-server version tag (e.g. v2.1.6)"
}

variable "region" {
  type        = string
  description = "DigitalOcean region to build in"
  default     = "nyc3"
}

variable "droplet_size" {
  type        = string
  description = "Droplet size for build"
  default     = "s-2vcpu-4gb"
}

locals {
  # Normalize version: accept both "v2.1.6" and "2.1.6"
  normalized_version = replace(var.version, "/^v/", "")
  tag                = "v${local.normalized_version}"
  snapshot_name      = "clever-vpn-server-${local.tag}"
}

source "digitalocean" "clever-vpn" {
  api_token     = var.do_token
  region        = var.region
  size          = var.droplet_size
  image         = "ubuntu-24-04-x64"
  snapshot_name = local.snapshot_name
  ssh_username  = "root"

  # Tags for identification
  tags = [
    "clever-vpn",
    "clever-vpn-server",
    "version-${local.tag}",
    "kubernetes-1-click"
  ]
}

build {
  sources = ["source.digitalocean.clever-vpn"]

  provisioner "shell" {
    environment_vars = [
      "APP_VERSION=${local.tag}",
    ]
    script = "${path.root}/scripts/install.sh"
  }

  # Post-install cleanup: remove cloud-init data and machine-specific state
  provisioner "shell" {
    inline = [
      "echo '=== Cleaning up for snapshot ==='",
      "rm -f /var/log/cloud-init*.log",
      "cloud-init clean --machine-id 2>/dev/null || true",
      "cloud-init clean --logs 2>/dev/null || true",
      "rm -f /etc/machine-id /var/lib/dbus/machine-id",
      "echo '' > /etc/machine-id 2>/dev/null || true",
      "echo '' > /var/lib/dbus/machine-id 2>/dev/null || true",
      "truncate -s 0 /root/.bash_history 2>/dev/null || true",
      "history -c 2>/dev/null || true",
      "echo '=== Snapshot cleanup complete ==='",
    ]
  }
}
