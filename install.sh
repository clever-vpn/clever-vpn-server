#!/usr/bin/env bash
set -euo pipefail

# ————————  配置部分 ————————
OWNER="clever-vpn"  # GitHub 用户名或组织名
REPO="clever-vpn-server"
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <TAG> [TOKEN]"
    exit 1
fi
TAG="$1"  # 比如 v1.2.3，或者你要安装的具体版本号
TOKEN="${2:-}"  # 可选的 TOKEN 参数
APP="clever-vpn-server"              # 二进制名称（解压后）
APPCMD="clever-vpn"

# ———————— 探测当前系统架构 ————————
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
# 检查当前系统是否满足 clever-vpn-server 的运行要求：
#   1. Linux 操作系统
#   2. systemd 支持
#   3. nftables (nft) 支持
#   4. eBPF 支持（BTF）
#   5. WireGuard 内核模块
check_environment() {
    local errors=0

    echo "=== Checking environment requirements ==="

    # 1. 检查是否为 Linux
    echo -n "[1/5] Checking Linux OS... "
    if [[ "$(uname -s)" == "Linux" ]]; then
        echo "OK ($(uname -s))"
    else
        echo "FAILED"
        echo "       ERROR: This script requires Linux. Detected OS: $(uname -s)"
        errors=$((errors + 1))
    fi

    # 2. 检查 systemd（通过 /run/systemd/system 目录或 pidof systemd）
    echo -n "[2/5] Checking systemd... "
    if [[ -d /run/systemd/system ]] || pidof systemd &>/dev/null; then
        echo "OK"
    else
        echo "FAILED"
        echo "       ERROR: systemd is required but not detected."
        echo "       clever-vpn-server runs as a systemd service."
        errors=$((errors + 1))
    fi

    # 3. 检查 nftables（nft 命令行工具）
    echo -n "[3/5] Checking nftables... "
    if command -v nft &>/dev/null; then
        echo "OK ($(nft --version 2>/dev/null | head -1 || echo 'installed'))"
    else
        echo "FAILED"
        echo "       ERROR: nftables (nft) is required but not found."
        echo "       Install it with: apt-get install nftables  or  yum install nftables"
        errors=$((errors + 1))
    fi

    # 4. 检查 eBPF（BTF 支持，通过 /sys/kernel/btf/vmlinux 判断）
    echo -n "[4/5] Checking eBPF (BTF)... "
    if [[ -f /sys/kernel/btf/vmlinux ]]; then
        echo "OK"
    else
        echo "FAILED"
        echo "       ERROR: eBPF BTF support not detected."
        echo "       Kernel must be compiled with CONFIG_DEBUG_INFO_BTF=y."
        echo "       Minimum recommended kernel version: 5.4+"
        errors=$((errors + 1))
    fi

    # 5. 检查 WireGuard 内核模块
    echo -n "[5/5] Checking WireGuard kernel module... "
    if [[ -d /sys/module/wireguard ]] || modprobe wireguard 2>/dev/null; then
        echo "OK"
    else
        echo "FAILED"
        echo "       ERROR: WireGuard kernel module is required but not available."
        echo "       Install it with: apt-get install wireguard  or  yum install wireguard-tools"
        echo "       For older kernels, you may need to install wireguard-dkms."
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

# ———————— patch 版本自动升级 ————————
# 当 TAG 是 vX.Y.Z 格式时，自动查找 vX.Y 中 Z 值最大的版本
auto_upgrade_patch() {
    local tag="$1"
    # 匹配 vX.Y.Z 格式（Z 为纯数字）
    if [[ "$tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        local major="${BASH_REMATCH[1]}"
        local minor="${BASH_REMATCH[2]}"
        local prefix="v${major}.${minor}."
        # 调试信息输出到 stderr，避免被 $() 捕获混入返回值
        echo "Detected patch version $tag, searching for latest in $prefix* ..." >&2
        # 通过 GitHub API 获取所有 releases，筛选 vX.Y.Z 格式，取最大 Z
        # 用 /releases 而非 /tags：后者包含无 release 的纯 tag
        local latest
        set +o pipefail
        latest=$(curl -sSL --connect-timeout 5 --max-time 10 \
            "https://api.github.com/repos/$OWNER/$REPO/releases?per_page=100" 2>/dev/null \
            | grep -oE '"tag_name": *"'"${prefix}[0-9]+"'"' \
            | grep -oE "${prefix}[0-9]+" \
            | sort -t '.' -k3 -n 2>/dev/null \
            | tail -1)
        set -o pipefail
        if [[ -n "$latest" ]]; then
            echo "Auto-upgraded to latest patch: $latest" >&2
            echo "$latest"
        else
            echo "Warning: no releases found matching $prefix*, using original tag $tag" >&2
            echo "$tag"
        fi
    else
        echo "$tag"
    fi
}

TAG=$(auto_upgrade_patch "$TAG")

# ———————— 构建下载 URL ————————
BASE_URL="https://github.com/$OWNER/$REPO/releases/download/$TAG"

# 文件名：多架构格式 clever-vpn-server-{arch}-{tag}，无架构格式 clever-vpn-server
GZ_ARCH="${APP}-${ARCH}-${TAG}.gz"
SHA_ARCH="${APP}-${ARCH}-${TAG}.sha256"
GZ="${APP}.gz"
SHA_FILE="${APP}.sha256"

# 探测 release 是否为多架构（通过检查 arch-specific 文件是否存在）
echo "Detecting release asset format..."
HTTP_CODE=$(curl -sI -o /dev/null -w "%{http_code}" "$BASE_URL/$GZ_ARCH")
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "302" ]]; then
    echo "Multi-architecture release detected. Using arch: $ARCH"
    GZ="$GZ_ARCH"
    SHA_FILE="$SHA_ARCH"
else
    echo "Arch-specific asset not found (HTTP $HTTP_CODE)."
    if [[ "$ARCH" == "amd64" ]]; then
        echo "Falling back to arch-less format (amd64 compatible)."
        # GZ 和 SHA_FILE 保持默认无架构命名
    else
        echo "ERROR: Architecture '$ARCH' is not supported for this release."
        echo "       Only amd64 can fall back to arch-less format."
        exit 1
    fi
fi

# ———————— 检查是否已安装 ————————
echo "Checking if clever-vpn is installed..."
if command -v clever-vpn &> /dev/null; then
    echo "clever-vpn is already installed. Please uninstall it first if you want to reinstall."
    exit 1
fi
echo "clever-vpn is not installed. Proceeding with installation..."

# ———————— 下载新版本 ————————
echo "Downloading $GZ and checksum..."
curl -L "$BASE_URL/$GZ" -o "$GZ"
curl -L "$BASE_URL/$SHA_FILE" -o "$SHA_FILE"

# ———————— 解压二进制 ————————
echo "Decompressing $GZ..."
# -f：如果已有同名文件，直接覆盖
gunzip -f "$GZ"

# 多架构模式下，解压后的文件名与 sha256 文件中引用的名称不一致，需要重命名
DECOMPRESSED="${GZ%.gz}"
if [[ "$DECOMPRESSED" != "$APP" ]]; then
    mv -f "$DECOMPRESSED" "$APP"
fi

# 校验
echo "Verifying checksum..."
sha256sum --check "$SHA_FILE"
echo "Checksum verified successfully."

# ———————— 安装新版本 ————————
echo "Installing new version..."
chmod +x "$APP"

# 确定使用的 token
INSTALL_TOKEN=""

if [[ -n "$TOKEN" ]]; then
    # 如果提供了 TOKEN 参数，使用它
    INSTALL_TOKEN="$TOKEN"
else
    echo "No token provided, installing without token."
fi

echo "Running '$APP install'..."
if [[ "${CI:-}" == "true" ]]; then
    echo "CI environment detected, skipping service installation."
else
    if [[ -n "$INSTALL_TOKEN" ]]; then
        ./"$APP" install -token="$INSTALL_TOKEN"
    else
        ./"$APP" install
    fi
fi
echo "Installation done."

# ———————— 清理临时文件 ————————
echo "Cleaning up..."
rm -f "$GZ" "$SHA_FILE" "$APP"

# ———————— 安装 bash 补全 ————————
BASH_COMPLETION_FILE="${APPCMD}.bash-completion"
BASH_COMPLETION_URL="https://github.com/$OWNER/$REPO/raw/main/${BASH_COMPLETION_FILE}"
echo "Downloading bash completion script..."
curl -L "$BASH_COMPLETION_URL" -o "$BASH_COMPLETION_FILE"
if [[ -f "$BASH_COMPLETION_FILE" ]]; then
    echo "Installing bash completion script to /etc/bash_completion.d/ (requires sudo)..."
    sudo mkdir -p /etc/bash_completion.d/
    sudo mv -f "$BASH_COMPLETION_FILE" /etc/bash_completion.d/
    echo "Bash completion installed."
else
    echo "Bash completion script not found."
fi

echo "Installation completed successfully!"
echo "clever-vpn server version $TAG has been installed."
