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

# ———————— patch 版本自动升级 ————————
# 当 TAG 是 vX.Y.Z 格式时，自动查找 vX.Y 中 Z 值最大的版本
auto_upgrade_patch() {
    local tag="$1"
    # 匹配 vX.Y.Z 格式（Z 为纯数字）
    if [[ "$tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        local major="${BASH_REMATCH[1]}"
        local minor="${BASH_REMATCH[2]}"
        local prefix="v${major}.${minor}."
        echo "Detected patch version $tag, searching for latest in $prefix* ..."
        # 获取所有 release tag，筛选 vX.Y.Z 格式，取最大 Z
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

# ———————— 确保 gh CLI 可用（仅 Linux） ————————
ensure_gh() {
    if command -v gh &> /dev/null; then
        return 0
    fi
    echo "gh CLI not found. Attempting to install..."
    if command -v apt-get &> /dev/null; then
        echo "Installing gh via apt-get (requires sudo)..."
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt-get update && sudo apt-get install -y gh
    elif command -v yum &> /dev/null; then
        echo "Installing gh via yum (requires sudo)..."
        sudo yum install -y gh
    elif command -v dnf &> /dev/null; then
        echo "Installing gh via dnf (requires sudo)..."
        sudo dnf install -y gh
    else
        echo "ERROR: No supported package manager found. Please install gh manually: https://cli.github.com/"
        return 1
    fi
    # 验证安装
    if command -v gh &> /dev/null; then
        echo "gh CLI installed successfully."
        return 0
    else
        echo "ERROR: gh CLI installation failed. Please install manually: https://cli.github.com/"
        return 1
    fi
}

if ensure_gh; then
    TAG=$(auto_upgrade_patch "$TAG")
else
    echo "Warning: proceeding without patch auto-upgrade."
fi

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
