#!/usr/bin/env bash
set -euo pipefail

# ————————  配置部分 ————————
# 请根据实际情况修改下面三个变量：
OWNER="clever-vpn"  # GitHub 用户名或组织名
REPO="clever-vpn-server"
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <TAG> <TOKEN>"
    exit 1
fi
TAG="$1"  # 比如 v1.2.3，或者你要安装的具体版本号
TOKEN="${2:-}"
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

# ———————— patch 版本自动升级 ————————
# 当 TAG 是 vX.Y.Z 格式时，自动查找 vX.Y 中 Z 值最大的版本
auto_upgrade_patch() {
    local tag="$1"
    if [[ "$tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        local major="${BASH_REMATCH[1]}"
        local minor="${BASH_REMATCH[2]}"
        local prefix="v${major}.${minor}."
        echo "Detected patch version $tag, searching for latest in $prefix* ..."
        local latest
        latest=$(gh release list -R "$OWNER/$REPO" --limit 200 --json tagName --jq '.[].tagName' \
            | grep -E "^${prefix}[0-9]+$" \
            | sort -t '.' -k3 -n \
            | tail -1)
        if [[ -n "$latest" ]]; then
            echo "Auto-upgraded to latest patch: $latest"
            echo "$latest"
        else
            echo "Warning: no releases found matching $prefix*, using original tag $tag"
            echo "$tag"
        fi
    else
        echo "$tag"
    fi
}

if command -v gh &> /dev/null; then
    TAG=$(auto_upgrade_patch "$TAG")
else
    echo "Warning: gh CLI not found, skipping patch auto-upgrade."
fi

# ———————— 构建下载 URL ————————
BASE_URL="https://github.com/$OWNER/$REPO/releases/download/$TAG"

GZ_ARCH="${APP}-${ARCH}-${TAG}.gz"
SHA_ARCH="${APP}-${ARCH}-${TAG}.sha256"
GZ="${APP}.gz"
SHA_FILE="${APP}.sha256"

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
    else
        echo "ERROR: Architecture '$ARCH' is not supported for this release."
        echo "       Only amd64 can fall back to arch-less format."
        exit 1
    fi
fi

# ———————— 下载资产 ————————
echo "Downloading $GZ and checksum..."
curl -L "$BASE_URL/$GZ" -o "$GZ"
curl -L "$BASE_URL/$SHA_FILE" -o "$SHA_FILE"

# ———————— 解压二进制 ————————
echo "Decompressing $GZ..."
# -f：如果已有同名文件，直接覆盖
gunzip -f "$GZ"

# 校验
echo "Verifying checksum..."
sha256sum --check "$SHA_FILE"
echo "Checksum verified successfully."

# ———————— 运行安装 ————————
echo "Running '$APP install'..."
chmod +x "$APP"
./"$APP" install -token="$TOKEN"
echo "Installation done."

# ———————— 安装 bash 补全 ————————
BASH_COMPLETION_FILE="${APPCMD}.bash-completion"
BASH_COMPLETION_URL="https://github.com/$OWNER/$REPO/raw/main/${BASH_COMPLETION_FILE}"
echo "Downloading bash completion script..."
curl -L "$BASH_COMPLETION_URL" -o "$BASH_COMPLETION_FILE"
if [[ -f "$BASH_COMPLETION_FILE" ]]; then
    echo "Installing bash completion script to /etc/bash_completion.d/ (requires sudo)..."
    sudo mkdir -p /etc/bash_completion.d/
    sudo mv -f "$BASH_COMPLETION_FILE" /etc/bash_completion.d/
    echo "Bash completion installed. please restart your shell or run 'source /etc/bash_completion.d/${BASH_COMPLETION_FILE}' to enable it. You can test it by typing '${APPCMD} <TAB><TAB>'."
else
    echo "Bash completion script not found."
fi

