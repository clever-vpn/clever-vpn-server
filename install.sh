#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# clever-vpn-server 安装脚本
# 用法: bash install.sh <TAG> [TOKEN]
#   TAG   - 版本号，如 v2.1.0（必填）
#   TOKEN - 激活令牌（可选，不提供则只安装不激活）
#
# 幂等设计：已安装时，有 TOKEN 则激活，无 TOKEN 则升级。
# ============================================================

OWNER="clever-vpn"
REPO="clever-vpn-server"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <TAG> [TOKEN]"
    echo "  TAG   - version tag, e.g. v2.1.0"
    echo "  TOKEN - activation token (optional)"
    exit 1
fi

TAG="$1"
TOKEN="${2:-}"
APP="clever-vpn-server"
APPCMD="clever-vpn"

# ———————— 探测系统架构 ————————
detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)   echo "amd64" ;;
        aarch64|arm64)  echo "arm64" ;;
        armv7l|armv6l)  echo "arm"   ;;
        i686|i386)      echo "386"   ;;
        *)              echo "$arch" ;;
    esac
}

ARCH=$(detect_arch)

# ———————— 环境检查 ————————
check_environment() {
    local errors=0

    echo "=== Checking environment requirements ==="

    echo -n "[1/5] Checking Linux OS... "
    if [[ "$(uname -s)" == "Linux" ]]; then
        echo "OK ($(uname -s))"
    else
        echo "FAILED"
        echo "       ERROR: This script requires Linux. Detected OS: $(uname -s)"
        errors=$((errors + 1))
    fi

    echo -n "[2/5] Checking systemd... "
    if [[ -d /run/systemd/system ]] || pidof systemd &>/dev/null; then
        echo "OK"
    else
        echo "FAILED"
        echo "       ERROR: systemd is required but not detected."
        errors=$((errors + 1))
    fi

    echo -n "[3/5] Checking nftables... "
    if command -v nft &>/dev/null; then
        echo "OK ($(nft --version 2>/dev/null | head -1 || echo 'installed'))"
    else
        echo "FAILED"
        echo "       ERROR: nftables (nft) is required but not found."
        echo "       Install it with: apt-get install nftables  or  yum install nftables"
        errors=$((errors + 1))
    fi

    echo -n "[4/5] Checking eBPF (BTF)... "
    if [[ -f /sys/kernel/btf/vmlinux ]]; then
        echo "OK"
    else
        echo "FAILED"
        echo "       ERROR: eBPF BTF support not detected."
        echo "       Kernel must be compiled with CONFIG_DEBUG_INFO_BTF=y (5.4+)."
        errors=$((errors + 1))
    fi

    echo -n "[5/5] Checking WireGuard kernel module... "
    if [[ -d /sys/module/wireguard ]] || modprobe wireguard 2>/dev/null; then
        echo "OK"
    else
        echo "FAILED"
        echo "       ERROR: WireGuard kernel module is required but not available."
        echo "       Install it with: apt-get install wireguard  or  yum install wireguard-tools"
        errors=$((errors + 1))
    fi

    echo ""

    if [[ $errors -gt 0 ]]; then
        echo "==========================================="
        echo "  $errors environment check(s) FAILED."
        echo "  Cannot proceed with installation."
        echo "  Please fix the issues above and try again."
        echo "==========================================="
        exit 1
    fi

    echo "All environment checks passed."
    echo ""
}

check_environment

# ———————— 已安装：幂等处理 ————————
if command -v "$APPCMD" &>/dev/null; then
    echo "clever-vpn is already installed."

    # 步骤 1：如果有 token，先激活
    if [[ -n "$TOKEN" ]]; then
        echo "Activating with new token..."
        "$APPCMD" activate -token="$TOKEN"
        echo "Activation completed successfully!"
    fi

    # 步骤 2：升级到指定版本（同版本自动跳过）
    echo "Upgrading to version $TAG..."
    "$APPCMD" update -tag="$TAG"
    echo "Update completed successfully!"

    exit 0
fi

# ———————— 未安装：完整安装流程 ————————
echo "clever-vpn is not installed. Proceeding with fresh installation..."

BASE_URL="https://github.com/$OWNER/$REPO/releases/download/$TAG"
GZ="${APP}-${ARCH}-${TAG}.gz"
SHA_FILE="${APP}-${ARCH}-${TAG}.sha256"

echo "Downloading $GZ and checksum..."
curl -L "$BASE_URL/$GZ" -o "$GZ"
curl -L "$BASE_URL/$SHA_FILE" -o "$SHA_FILE"

echo "Decompressing $GZ..."
gunzip -f "$GZ"

# 解压后文件名与 sha256 文件中引用的名称可能不一致，统一重命名
DECOMPRESSED="${GZ%.gz}"
if [[ "$DECOMPRESSED" != "$APP" ]]; then
    mv -f "$DECOMPRESSED" "$APP"
fi

echo "Verifying checksum..."
sha256sum --check "$SHA_FILE"
echo "Checksum verified successfully."

echo "Installing new version..."
chmod +x "$APP"

if [[ "${CI:-}" == "true" ]]; then
    echo "CI environment detected, skipping service installation."
else
    if [[ -n "$TOKEN" ]]; then
        ./"$APP" install -token="$TOKEN"
    else
        ./"$APP" install
    fi
fi

echo "Cleaning up..."
rm -f "$GZ" "$SHA_FILE" "$APP"

# ———————— bash 补全 ————————
BASH_COMPLETION_FILE="${APPCMD}.bash-completion"
BASH_COMPLETION_URL="https://github.com/$OWNER/$REPO/raw/main/${BASH_COMPLETION_FILE}"
echo "Downloading bash completion script..."
if curl -sL "$BASH_COMPLETION_URL" -o "$BASH_COMPLETION_FILE" 2>/dev/null && [[ -f "$BASH_COMPLETION_FILE" ]]; then
    sudo mkdir -p /etc/bash_completion.d/
    sudo mv -f "$BASH_COMPLETION_FILE" /etc/bash_completion.d/
    echo "Bash completion installed."
fi

echo ""
echo "==========================================="
echo "  Installation completed successfully!"
echo "  clever-vpn server version $TAG has been installed."
echo "==========================================="
