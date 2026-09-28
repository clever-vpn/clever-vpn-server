#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# clever-vpn-server 安装脚本
# 用法: bash install.sh <TAG> [TOKEN] [--local-file <PATH>]
#   TAG   - 版本号，如 v2.1.0（必填）
#   TOKEN - 激活令牌（可选，不提供则只安装不激活）
#   --local-file - 用本地已备好的发布产物（.gz）替代下载；同目录存在同名
#                  .sha256 时一并校验。用于手工验证与离线安装。
#
# 幂等设计：已安装时，有 TOKEN 则激活，无 TOKEN 则升级；
# 带 --local-file 时改为原地替换二进制并重启（不下载、不卸载）。
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
# 发布资产镜像（Cloudflare R2 + 自定义域），key 形状 = vpn-server/<TAG>/<asset>
R2_BASE_URL="https://download.clever-vpn.org/vpn-server"

usage() {
    cat >&2 <<'EOF'
Usage: install.sh <TAG> [TOKEN] [--local-file <PATH>]
  TAG   - version tag, e.g. v2.1.0 (required)
  TOKEN - activation token (optional; without it the server is installed
          but not activated)
  --local-file <PATH> - install from a local release artifact instead of
          downloading. PATH must be the released .gz
          (e.g. clever-vpn-server-amd64-v2.1.11.gz); a sibling .sha256 is
          verified when present.
EOF
}

APP="clever-vpn-server"
APPCMD="clever-vpn"
LOCAL_FILE=""
POSITIONAL=()

# 位置参数保持 <TAG> [TOKEN] 不变 —— 生产环境的调用形式是
# `bash -c "$(curl ...)" @ "<TAG>" "<TOKEN>"`（@ 是 $0 占位符），不能改。
while [[ $# -gt 0 ]]; do
    case "$1" in
        --local-file)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: --local-file requires a path argument." >&2
                usage
                exit 1
            fi
            LOCAL_FILE="$2"
            shift 2
            ;;
        --local-file=*)
            LOCAL_FILE="${1#*=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

if [[ ${#POSITIONAL[@]} -gt 0 ]]; then
    set -- "${POSITIONAL[@]}"
else
    set --
fi

if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

TAG="$1"
TOKEN="${2:-}"

# TAG 会被拼进下载 URL（引导层里它还是平台可配置的值），先做白名单。
# 允许 v1.2.3 与 v1.2.3-rc.1 —— 后者用于手工验证 RC。
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]]; then
    echo "ERROR: invalid TAG '$TAG', expected v<major>.<minor>.<patch> (optionally -rc.<n>)." >&2
    exit 1
fi

if [[ -n "$LOCAL_FILE" ]]; then
    if [[ ! -f "$LOCAL_FILE" ]]; then
        echo "ERROR: --local-file path not found: $LOCAL_FILE" >&2
        exit 1
    fi
    if [[ "$LOCAL_FILE" != *.gz ]]; then
        echo "ERROR: --local-file expects the release .gz artifact, got: $LOCAL_FILE" >&2
        exit 1
    fi
fi

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
#
# 返回：0 = 成功；2 = 该源上没有这份文件（换源即可，重试无意义）；1 = 其它失败
download_file() {
    local url="$1" dest="$2" min_bytes="${3:-1}"
    local attempt tries rc size remaining attempt_timeout elapsed http_code ok

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
        http_code=""

        if [[ "$DOWNLOADER" == "curl" ]]; then
            # 这里刻意**不用 -f**：要把「这个源上没有这份文件」(403/404/410) 与
            # 「传输失败」(超时/5xx) 区分开 —— 前者重试同一个源毫无意义，应当立刻换源。
            # 代价是 4xx/5xx 的响应体会落进 .tmp，所以下面显式要求 HTTP 200。
            http_code=$(curl -sS -L --proto '=https' --connect-timeout 10 \
                --max-time "$attempt_timeout" -o "${dest}.tmp" -w '%{http_code}' "$url") || rc=$?
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

        ok=0
        if [[ "$DOWNLOADER" == "curl" ]]; then
            if [[ "$rc" -eq 0 && "$http_code" == "200" && "$size" -ge "$min_bytes" ]]; then
                ok=1
            fi
        else
            if [[ "$rc" -eq 0 && "$size" -ge "$min_bytes" ]]; then
                ok=1
            fi
        fi

        if [[ $ok -eq 1 ]]; then
            mv -f "${dest}.tmp" "$dest"
            return 0
        fi

        rm -f "${dest}.tmp"

        # 「源上明确没有这份文件」⇒ 立刻返回 2，让调用方换源（而不是白重试 3 次）
        case "$http_code" in
            403|404|410)
                echo "  HTTP $http_code: $url is not available on this source" >&2
                return 2
                ;;
        esac

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

# ———————— 产物就位与校验 ————————
GZ="${APP}-${ARCH}-${TAG}.gz"
SHA_FILE="${APP}-${ARCH}-${TAG}.sha256"

# 候选下载源，按优先级排列（"标签|基址"）；实际 URL = <基址>/<TAG>/<asset>。
# 两处的 URL 形状**同构**，所以换源只是换一个基址。
#   ① R2 镜像在前：主源，正是为了摆脱 GitHub 那个 CDN 的抖动；
#   ② GitHub 必须留在列表里 —— v2.0.1 起所有已部署的二进制都只认公开仓
#      releases/download 的形状（不可变的对外契约）。
SOURCES=(
    "R2|${R2_BASE_URL}"
    "GitHub|https://github.com/$OWNER/$REPO/releases/download"
)

# prepare_artifact：把待安装的二进制就位（产出可执行的 ./$APP）。返回 0 = 就绪。
#   - 带 --local-file：用本地已备好的产物（gzip → 校验 → 解压，与联网路径同一条路）
#   - 否则：按 SOURCES 逐个源「取包 + 校验」，**任一源完整通过即止**；
#     取包失败或校验失败都换下一个源 —— 镜像抖动、半截对象都能自动落到 GitHub。
prepare_artifact() {
    if [[ -n "$LOCAL_FILE" ]]; then
        local base sibling_sha
        base="$(basename -- "$LOCAL_FILE")"
        if [[ "$base" != "$GZ" ]]; then
            echo "WARNING: local artifact is named '$base', expected '$GZ' (arch=$ARCH, tag=$TAG)." >&2
            echo "         Continuing, but double-check its architecture and version." >&2
        fi
        echo "Using local artifact: $LOCAL_FILE"
        cp -f -- "$LOCAL_FILE" "$GZ"

        sibling_sha="${LOCAL_FILE%.gz}.sha256"
        if [[ -f "$sibling_sha" ]]; then
            cp -f -- "$sibling_sha" "$SHA_FILE"
        else
            echo "WARNING: no $sibling_sha next to the local artifact - checksum verification will be skipped." >&2
        fi

        if verify_and_extract; then
            return 0
        fi
        return 1
    fi

    local entry label base rc
    for entry in "${SOURCES[@]}"; do
        label="${entry%%|*}"
        base="${entry#*|}"

        echo "Fetching $GZ (arch: $ARCH) from $label..."
        rc=0
        download_file "$base/$GZ" "$GZ" "$MIN_ARTIFACT_BYTES" || rc=$?
        if [[ $rc -eq 0 ]]; then
            echo "Fetching $SHA_FILE from $label..."
            download_file "$base/$SHA_FILE" "$SHA_FILE" 64 || rc=$?
        fi

        if [[ $rc -ne 0 ]]; then
            if [[ $rc -eq 2 ]]; then
                echo "WARNING: $label has no $TAG assets; trying the next source." >&2
            else
                echo "WARNING: $label download failed (rc=$rc); trying the next source." >&2
            fi
            continue
        fi

        if verify_and_extract; then
            return 0
        fi
        echo "WARNING: $label artifact failed verification; trying the next source." >&2
    done

    echo "ERROR: all ${#SOURCES[@]} download sources failed for $TAG" >&2
    return 1
}

# verify_and_extract：格式预检 → gzip -t → 解压改名 → sha256 校验，产出可执行的 ./$APP。
# 返回 0 = 通过；非 0 = 这个源的产物不可用（由调用方决定换源还是报错）。
verify_and_extract() {
    if [[ -f "$SHA_FILE" ]]; then
        # 校验文件自检：截断或错误页会让 sha256sum 报出难以理解的格式错误，这里提前拦下
        if ! grep -Eq '^[0-9a-f]{64} +[^ ]+$' "$SHA_FILE"; then
            echo "ERROR: malformed checksum file ($SHA_FILE), expected '<64-hex-digest>  <filename>'." >&2
            echo "       The download was most likely truncated - please re-run the installer." >&2
            return 1
        fi
    fi

    # 解压前先做完整性测试：截断的归档在这里就会被抓住，且不会留下半截二进制
    echo "Testing archive integrity..."
    if ! gzip -t "$GZ"; then
        echo "ERROR: $GZ is truncated or corrupted (gzip integrity test failed)." >&2
        echo "       The download was most likely cut short - please re-run the installer." >&2
        return 1
    fi

    echo "Decompressing $GZ..."
    gunzip -f "$GZ"

    # 解压后文件名与 sha256 文件中引用的名称可能不一致，统一重命名
    DECOMPRESSED="${GZ%.gz}"
    if [[ "$DECOMPRESSED" != "$APP" ]]; then
        mv -f "$DECOMPRESSED" "$APP"
    fi

    if [[ -f "$SHA_FILE" ]]; then
        echo "Verifying checksum..."
        if ! sha256sum --check "$SHA_FILE"; then
            echo "ERROR: checksum verification failed for $SHA_FILE." >&2
            return 1
        fi
        echo "Checksum verified successfully."
    else
        echo "WARNING: checksum file unavailable - integrity NOT verified." >&2
    fi

    chmod +x "$APP"
}

# ———————— 已安装：幂等处理 ————————
if command -v "$APPCMD" &>/dev/null; then
    echo "clever-vpn is already installed."

    # 步骤 1：如果有 token，先激活
    if [[ -n "$TOKEN" ]]; then
        echo "Activating with new token..."
        "$APPCMD" activate -token="$TOKEN"
        echo "Activation completed successfully!"
    fi

    # 步骤 2：替换二进制
    if [[ -n "$LOCAL_FILE" ]]; then
        # 本地旁路：原地替换二进制并重启，等价于 `update`，但不下载。
        # 刻意不走 uninstall：uninstall 会删掉 /etc/clever-vpn-server/，
        # 而平台写入的 wsUrl / token 配置就在那里 —— 那会让这台机器再也连不上平台。
        prepare_artifact

        TARGET="$(readlink -f "$(command -v "$APPCMD")")"
        if [[ -z "$TARGET" || ! -f "$TARGET" ]]; then
            echo "ERROR: cannot resolve the installed binary path from '$APPCMD'." >&2
            exit 1
        fi

        echo "Replacing $TARGET ..."
        "$APPCMD" stop
        cp -f "$APP" "${TARGET}.new"
        chmod +x "${TARGET}.new"
        # 同目录 rename：原子替换
        mv -f "${TARGET}.new" "$TARGET"
        "$APPCMD" start
        echo "Replaced with the local artifact ($TAG) and restarted."
    else
        # 升级到指定版本（同版本自动跳过，由 Go 侧判断）
        echo "Upgrading to version $TAG..."
        "$APPCMD" update -tag="$TAG"
        echo "Update completed successfully!"
    fi

    exit 0
fi

# ———————— 未安装：完整安装流程 ————————
echo "clever-vpn is not installed. Proceeding with fresh installation..."

prepare_artifact

echo "Installing new version..."

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
