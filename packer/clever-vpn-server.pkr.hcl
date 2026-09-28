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
  default     = "s-1vcpu-1gb"
}

locals {
  # Normalize version: accept both "v2.1.6" and "2.1.6"
  normalized_version = trimprefix(var.version, "v")
  tag                = "v${local.normalized_version}"
  # DO tags cannot contain dots — replace with dashes
  tag_safe           = replace(local.tag, ".", "-")
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
    "version-${local.tag_safe}",
    "kubernetes-1-click"
  ]
}

build {
  sources = ["source.digitalocean.clever-vpn"]

  # 取该版本的 install.sh 并运行。脚本随发布走（与二进制同一次发布）：
  #   R2 主源  https://download.clever-vpn.org/vpn-server/<TAG>/install.sh
  #   GitHub  https://github.com/clever-vpn/clever-vpn-server/releases/download/<TAG>/install.sh
  # 刻意不再上传仓库里那份 —— 那份现在只是给老 URL 用的兼容壳。
  # 保留兜底：构建机的出口 IP 可能被公开域名的边缘策略挡（CI runner 就是这个原因）。
  # 无 token —— 这里只做 base snapshot（不含激活信息）。
  provisioner "shell" {
    inline = [
      "set -e",
      "curl -fsSL --connect-timeout 10 --max-time 60 https://download.clever-vpn.org/vpn-server/${local.tag}/install.sh -o /tmp/install.sh || curl -fsSL --connect-timeout 10 --max-time 60 https://github.com/clever-vpn/clever-vpn-server/releases/download/${local.tag}/install.sh -o /tmp/install.sh",
      "bash -n /tmp/install.sh",
      "bash /tmp/install.sh ${local.tag}",
      "rm -f /tmp/install.sh",
    ]
  }

  # ── Marketplace compliance ───────────────────────────────
  # 1. Install all security updates (required by img_check.sh)
  # 2. Install & configure ufw firewall
  # 3. Clear SSH keys, logs, and machine-specific state
  provisioner "shell" {
    inline = [
      "echo '=== Installing security updates ==='",
      "apt-get update -y",
      "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::='--force-confold'",
      "echo '=== Installing ufw firewall ==='",
      "apt-get install -y ufw",
      "ufw allow OpenSSH",
      "echo '=== Cleaning up for Marketplace snapshot ==='",
      "# Clear Packer SSH key",
      "echo '' > /root/.ssh/authorized_keys",
      "# Clear machine-specific IDs",
      "rm -f /etc/machine-id /var/lib/dbus/machine-id",
      "echo '' > /etc/machine-id 2>/dev/null || true",
      "echo '' > /var/lib/dbus/machine-id 2>/dev/null || true",
      "# Clear shell history",
      "truncate -s 0 /root/.bash_history 2>/dev/null || true",
      "history -c 2>/dev/null || true",
      "# Clear DHCP leases",
      "rm -f /var/lib/dhcp/*.leases 2>/dev/null || true",
      "# Clear log files checked by img_check.sh",
      "truncate -s 0 /var/log/auth.log 2>/dev/null || true",
      "truncate -s 0 /var/log/kern.log 2>/dev/null || true",
      "truncate -s 0 /var/log/dpkg.log 2>/dev/null || true",
      "truncate -s 0 /var/log/unattended-upgrades/*.log 2>/dev/null || true",
      "truncate -s 0 /var/log/dmesg 2>/dev/null || true",
      "# Reset cloud-init so next boot is a fresh first-boot",
      "cloud-init clean --machine-id 2>/dev/null || true",
      "cloud-init clean --logs 2>/dev/null || true",
      "echo '=== Marketplace cleanup complete ==='",
    ]
  }
}
