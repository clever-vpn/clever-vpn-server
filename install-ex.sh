#!/usr/bin/env bash
set -euo pipefail

# ————————  配置部分 ————————
# 请根据实际情况修改下面三个变量：
OWNER="clever-vpn"  # GitHub 用户名或组织名
REPO="clever-vpn-server"
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <TAG>"
    exit 1
fi
TAG="$1"  # 比如 v1.2.3，或者你要安装的具体版本号
TOKEN="$2"
APP="clever-vpn-server"              # 二进制名称（解压后）
APPCMD="clever-vpn"
GZ="${APP}.gz"
SHA_FILE="${APP}.sha256"
# GitHub Releases 下载 URL 前缀
BASE_URL="https://github.com/$OWNER/$REPO/releases/download/$TAG"

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
# if [[ -n "${TOKEN}" ]]; then
#    "$APPCMD" activate -token="$TOKEN"
# fi
echo "Installation done."

# ———————— 安装 bash 补全 ————————
BASH_COMPLETION_FILE="${APPCMD}.bash-completion"
BASH_COMPLETION_URL="https://github.com/$OWNER/$REPO/raw/main/${BASH_COMPLETION_FILE}"
echo "Downloading bash completion script..."
curl -L "$BASH_COMPLETION_URL" -o "$BASH_COMPLETION_FILE"
if [[ -f "$BASH_COMPLETION_FILE" ]]; then
    echo "Installing bash completion script to /etc/bash_completion.d/ (requires sudo)..."
    sudo mv -f "$BASH_COMPLETION_FILE" /etc/bash_completion.d/
    echo "Bash completion installed. please restart your shell or run 'source /etc/bash_completion.d/${BASH_COMPLETION_FILE}' to enable it. You can test it by typing '${APPCMD} <TAB><TAB>'."
else
    echo "Bash completion script not found."
fi

