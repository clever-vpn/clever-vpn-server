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

# 配置文件路径
CONFIG_DIR="/etc/clever-vpn-server"
CONFIG_FILE="${CONFIG_DIR}/clever-vpn-server.conf"
TOKEN_FILE="${CONFIG_DIR}/token"

# 备份文件路径
BACKUP_DIR="/tmp/clever-vpn-backup"
BACKUP_CONFIG_FILE="${BACKUP_DIR}/clever-vpn-server.conf"
BACKUP_TOKEN_FILE="${BACKUP_DIR}/token"

# ———————— 检查是否已安装 ————————
echo "Checking if clever-vpn is installed..."
if ! command -v clever-vpn &> /dev/null; then
    echo "clever-vpn is not installed. Proceeding with fresh installation..."
    FRESH_INSTALL=true
else
    echo "clever-vpn found. Proceeding with upgrade..."
    FRESH_INSTALL=false
    
    # ———————— 备份配置文件 ————————
    echo "Backing up configuration files..."
    mkdir -p "$BACKUP_DIR"

    # 备份配置文件（如果存在）
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "Backing up $CONFIG_FILE..."
        cp "$CONFIG_FILE" "$BACKUP_CONFIG_FILE"
        echo "Configuration file backed up."
    else
        echo "Configuration file $CONFIG_FILE does not exist."
    fi

    # 备份 token 文件（如果存在）
    if [[ -f "$TOKEN_FILE" ]]; then
        echo "Backing up $TOKEN_FILE..."
        cp "$TOKEN_FILE" "$BACKUP_TOKEN_FILE"
        echo "Token file backed up."
    else
        echo "Token file $TOKEN_FILE does not exist."
    fi

    # ———————— 卸载现有服务 ————————
    echo "Uninstalling existing clever-vpn server..."
    clever-vpn uninstall || echo "Warning: uninstall command failed, continuing anyway..."
fi

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
elif [[ "$FRESH_INSTALL" == "false" && -f "$BACKUP_TOKEN_FILE" ]]; then
    # 如果是升级且有备份的 token 文件，读取它
    INSTALL_TOKEN=$(cat "$BACKUP_TOKEN_FILE")
    echo "Using token from backup file."
else
    echo "Error: No token provided and no backup token file found."
    exit 1
fi

echo "Running '$APP install'..."
./"$APP" install -token="$INSTALL_TOKEN"
echo "Installation done."

# ———————— 恢复配置文件 ————————
if [[ "$FRESH_INSTALL" == "false" ]]; then
    echo "Restoring configuration files..."

    # 恢复配置文件（如果有备份）
    if [[ -f "$BACKUP_CONFIG_FILE" ]]; then
        echo "Restoring configuration file..."
        sudo mkdir -p "$CONFIG_DIR"
        sudo cp "$BACKUP_CONFIG_FILE" "$CONFIG_FILE"
        echo "Configuration file restored."
    fi
else
    echo "Fresh installation completed. No configuration to restore."
fi

# ———————— 清理备份和临时文件 ————————
echo "Cleaning up..."
if [[ "$FRESH_INSTALL" == "false" ]]; then
    rm -rf "$BACKUP_DIR"
fi
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

if [[ "$FRESH_INSTALL" == "true" ]]; then
    echo "Installation completed successfully!"
    echo "clever-vpn server version $TAG has been installed."
else
    echo "Upgrade completed successfully!"
    echo "clever-vpn server has been upgraded to version $TAG."
fi
