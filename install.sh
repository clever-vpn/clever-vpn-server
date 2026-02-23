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
GZ="${APP}.gz"
SHA_FILE="${APP}.sha256"
# GitHub Releases 下载 URL 前缀
BASE_URL="https://github.com/$OWNER/$REPO/releases/download/$TAG"

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
if [[ -n "$INSTALL_TOKEN" ]]; then
    ./"$APP" install -token="$INSTALL_TOKEN"
else
    ./"$APP" install
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
