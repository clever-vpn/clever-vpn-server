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

# ———————— 失败诊断与清理 ————————
# 出错时打印行号（便于从 cloud-init 日志定位）；退出时清理本次安装产生的文件，
# 包括 .tmp 半截文件，避免残留物被下一次运行误用。
cleanup() {
    local f
    for f in "${GZ:-}" "${DECOMPRESSED:-}" "${SHA_FILE:-}" "${APP:-}" "${BASH_COMPLETION_FILE:-}"; do
        if [[ -n "$f" ]]; then
            rm -f "$f" "$f.tmp" 2>/dev/null || true
        fi
    done
    return 0
}
trap cleanup EXIT
trap 'echo "ERROR: install.sh aborted at line $LINENO (exit code $?)" >&2' ERR

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

# ———————— 下载工具 ————————
# curl 优先（主流服务器发行版预置率更高，且本脚本的引导层也是 curl），回退 wget。
# 探测结果不在这里硬失败：已安装分支走 `clever-vpn update`（Go 侧自建连接）并不需要它，
# 只有真正需要下载时才由 require_downloader 给出明确、可操作的错误。
DOWNLOADER=""
MIN_ARTIFACT_BYTES=1000000  # 发布包约 10MB，用它挡住错误页/空响应
MAX_DOWNLOAD_ATTEMPTS=3     # 尝试次数上限（含首次）
DOWNLOAD_MAX_TIME=180       # 单次尝试超时（秒）：10.6MB 需 ~60KB/s，有效网络绰绰有余
DOWNLOAD_RETRY_DELAY=3      # 重试间隔（秒）：内层只负责抗瞬时抖动
DOWNLOAD_TOTAL_BUDGET=300   # 全部下载共享的总预算（秒）：到点即放弃，交给外层重试

detect_downloader() {
    if command -v curl &>/dev/null; then
        DOWNLOADER="curl"
    elif command -v wget &>/dev/null; then
        DOWNLOADER="wget"
    fi
}

require_downloader() {
    [[ -n "$DOWNLOADER" ]] && return 0
    cat >&2 <<'EOF'
ERROR: neither curl nor wget is installed, but a download is required.
       Install one of them and re-run this script:
         Debian/Ubuntu : apt-get update && apt-get install -y curl
         RHEL/Rocky    : dnf install -y curl-minimal
         Alpine        : apk add --no-cache curl
EOF
    exit 1
}

# download_file <url> <dest> [min_bytes]
# 下载单个文件：失败自动重试，且整包重下（不做续传，避免 200/206 语义差异
# 导致文件被静默损坏）。先写 <dest>.tmp，确认完整后才原子替换 <dest>，
# 因此任何时刻都不会留下可被误当成完整文件的半截文件。
#
# 时间预算：内层只负责抗「瞬时抖动」（秒级），分钟级的「网络尚未就绪」交给外层重试。
#   - 单次尝试最长 DOWNLOAD_MAX_TIME 秒，并受剩余总预算裁剪
#   - 全部下载共享 DOWNLOAD_TOTAL_BUDGET 秒总预算，到点即放弃
#   次数与预算取先到者：失败很快时能用满 MAX_DOWNLOAD_ATTEMPTS 次；
#   单次就卡满超时的连接可能在预算耗尽时提前放弃（这类连接重试收益本就低）。
download_file() {
    local url="$1" dest="$2" min_bytes="${3:-1}"
    local attempt tries rc size remaining attempt_timeout elapsed

    require_downloader

    # 首次调用时启动全局预算时钟（多个文件共享同一个预算）
    if [[ -z "${DOWNLOAD_STARTED:-}" ]]; then
        DOWNLOAD_STARTED=$SECONDS
        DOWNLOAD_DEADLINE=$((SECONDS + DOWNLOAD_TOTAL_BUDGET))
    fi

    for ((attempt = 1; attempt <= MAX_DOWNLOAD_ATTEMPTS; attempt++)); do
        remaining=$((DOWNLOAD_DEADLINE - SECONDS))
        if [[ $remaining -le 0 ]]; then
            echo "  download budget of ${DOWNLOAD_TOTAL_BUDGET}s exhausted" >&2
            break
        fi
        # 取「剩余预算」与「单次上限」中的较小值，保证总耗时不会超出预算
        if [[ $remaining -lt $DOWNLOAD_MAX_TIME ]]; then
            attempt_timeout=$remaining
        else
            attempt_timeout=$DOWNLOAD_MAX_TIME
        fi

        rm -f "${dest}.tmp"
        rc=0

        if [[ "$DOWNLOADER" == "curl" ]]; then
            # -f 必须保留：否则 4xx/5xx 会以退出码 0 把错误页写进文件
            curl -fL --proto '=https' --connect-timeout 10 --max-time "$attempt_timeout" \
                -o "${dest}.tmp" "$url" || rc=$?
        else
            # 重试由本函数统一负责，故 --tries=1，让日志与退避可控
            wget -q --tries=1 --timeout="$attempt_timeout" --https-only \
                -O "${dest}.tmp" "$url" || rc=$?
        fi

        if [[ -f "${dest}.tmp" ]]; then
            size=$(wc -c <"${dest}.tmp" | tr -d '[:space:]')
        else
            size=0
        fi

        if [[ "$rc" -eq 0 && "$size" -ge "$min_bytes" ]]; then
            mv -f "${dest}.tmp" "$dest"
            return 0
        fi

        rm -f "${dest}.tmp"
        if [[ $attempt -lt $MAX_DOWNLOAD_ATTEMPTS ]]; then
            echo "  attempt $attempt/$MAX_DOWNLOAD_ATTEMPTS failed (exit=$rc, ${size} bytes); retrying in ${DOWNLOAD_RETRY_DELAY}s..." >&2
            sleep "$DOWNLOAD_RETRY_DELAY"
        fi
    done

    tries=$((attempt - 1))
    elapsed=$((SECONDS - DOWNLOAD_STARTED))
    if [[ $tries -eq 0 ]]; then
        echo "ERROR: download budget (${DOWNLOAD_TOTAL_BUDGET}s) exhausted before trying: $url" >&2
    else
        echo "ERROR: download failed after ${tries} attempt(s), ${elapsed}s elapsed: $url" >&2
    fi
    return 1
}

# ———————— 环境检查 ————————
check_environment() {
    local errors=0 skipped=0 ci_mode=0

    # CI 模式（如 GitHub runner）无法满足硬件相关前置条件：runner 上 modprobe 以非 root
    # 执行必然失败，BTF 也可能缺失。这两项降级为 SKIPPED，让测试能跑到下载/校验逻辑；
    # 真实机器上不受影响，依旧强制检查。
    if [[ "${CI:-}" == "true" ]]; then
        ci_mode=1
    fi

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

    echo -n "[3/5] Checking eBPF (BTF)... "
    if [[ $ci_mode -eq 1 ]]; then
        echo "SKIPPED (CI)"
        skipped=$((skipped + 1))
    elif [[ -f /sys/kernel/btf/vmlinux ]]; then
        echo "OK"
    else
        echo "FAILED"
        echo "       ERROR: eBPF BTF support not detected."
        echo "       Kernel must be compiled with CONFIG_DEBUG_INFO_BTF=y (5.4+)."
        errors=$((errors + 1))
    fi

    echo -n "[4/5] Checking WireGuard kernel module... "
    if [[ $ci_mode -eq 1 ]]; then
        echo "SKIPPED (CI)"
        skipped=$((skipped + 1))
    elif [[ -d /sys/module/wireguard ]] || modprobe wireguard 2>/dev/null; then
        echo "OK"
    else
        echo "FAILED"
        echo "       ERROR: WireGuard kernel module is required but not available."
        echo "       Install it with: apt-get install wireguard  or  yum install wireguard-tools"
        errors=$((errors + 1))
    fi

    # 注意：不计入 errors。没有下载工具时，已安装的分支（activate/update）
    # 依然可用，因此只在真正需要下载时由 require_downloader 明确报错退出。
    echo -n "[5/5] Checking download tool... "
    detect_downloader
    if [[ -n "$DOWNLOADER" ]]; then
        echo "OK ($DOWNLOADER)"
    else
        echo "NOT FOUND"
        echo "       NOTE: neither curl nor wget is available."
        echo "       Activating/updating an existing installation still works,"
        echo "       but a fresh installation will abort when it needs to download."
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

    if [[ $skipped -gt 0 ]]; then
        echo "All environment checks passed ($skipped hardware check(s) skipped in CI)."
    else
        echo "All environment checks passed."
    fi
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

echo "Downloading $GZ (arch: $ARCH)..."
download_file "$BASE_URL/$GZ" "$GZ" "$MIN_ARTIFACT_BYTES"

echo "Downloading $SHA_FILE..."
download_file "$BASE_URL/$SHA_FILE" "$SHA_FILE" 64

# 校验文件自检：截断或错误页会让 sha256sum 报出难以理解的格式错误，这里提前拦下
if ! grep -Eq '^[0-9a-f]{64} +[^ ]+$' "$SHA_FILE"; then
    echo "ERROR: malformed checksum file ($SHA_FILE), expected '<64-hex-digest>  <filename>'." >&2
    echo "       The download was most likely truncated - please re-run the installer." >&2
    exit 1
fi

# 解压前先做完整性测试：截断的归档在这里就会被抓住，且不会留下半截二进制
echo "Testing archive integrity..."
if ! gzip -t "$GZ"; then
    echo "ERROR: $GZ is truncated or corrupted (gzip integrity test failed)." >&2
    echo "       The download was most likely cut short - please re-run the installer." >&2
    exit 1
fi

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

# 中间产物（$GZ / $SHA_FILE / $APP）由 EXIT trap 统一清理

# ———————— bash 补全 ————————
# 从 $TAG 取而不是可变的 main，保证脚本与补全脚本版本一致
BASH_COMPLETION_FILE="${APPCMD}.bash-completion"
BASH_COMPLETION_URL="https://github.com/$OWNER/$REPO/raw/$TAG/${BASH_COMPLETION_FILE}"

install_bash_completion() {
    local dest="/etc/bash_completion.d"
    # root 环境下 sudo 可能根本不存在，不能无条件依赖它
    if [[ "$EUID" -eq 0 ]]; then
        mkdir -p "$dest" && mv -f "$BASH_COMPLETION_FILE" "$dest/"
    elif command -v sudo &>/dev/null; then
        sudo mkdir -p "$dest" && sudo mv -f "$BASH_COMPLETION_FILE" "$dest/"
    else
        echo "WARNING: skipping bash completion (not root, sudo unavailable)." >&2
        return 1
    fi
}

echo "Downloading bash completion script..."
# 补全是可选功能，失败不应影响已完成的安装
if download_file "$BASH_COMPLETION_URL" "$BASH_COMPLETION_FILE" 16; then
    if install_bash_completion; then
        echo "Bash completion installed."
    fi
else
    echo "WARNING: could not download bash completion script (non-fatal)." >&2
fi

echo ""
echo "==========================================="
echo "  Installation completed successfully!"
echo "  clever-vpn server version $TAG has been installed."
echo "==========================================="
