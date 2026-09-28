#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# 兼容壳（tombstone）—— 这里曾经是真安装脚本的入口：
#
#   bash -c "$(curl -L https://github.com/clever-vpn/clever-vpn-server/raw/main/install.sh)" @ "<TAG>" "<TOKEN>"
#
# 安装脚本现在随**发布产物**走，与二进制同一次发布、同一个基址：
#
#   R2             https://download.clever-vpn.org/vpn-server/<TAG>/install.sh
#   GitHub release https://github.com/clever-vpn/clever-vpn-server/releases/download/<TAG>/install.sh
#
# 本壳按入参里的 <TAG> 取**那个版本**的真脚本并原地执行 —— 老命令、老博客、
# 用户收藏的旧文档里的这个 URL 因此永远还能用，语义与当年一致（当年这个 URL
# 取到的也正是该 tag 的脚本）。
#
# 真身住在私有仓 clever-vpn-server-src 的根目录（随发布发到上面两个位置）。
# 这个文件只是迁移期的一层壳，将来可以删。
#
# CLEVER_VPN_INSTALL_SHIM=1 —— 下面用它判断“取回来的居然又是这个壳”（自我递归），
# 只挡壳、不挡别的：第三个源里躺的是历史 tag 的真脚本，它们没有新脚本的契约标记。
# ============================================================

TAG="${1:-}"
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]]; then
    echo "ERROR: usage: install.sh <TAG> [TOKEN]  (TAG 形如 v2.1.10)" >&2
    echo "       This URL is only a compatibility shim. The real installer is at" >&2
    echo "       https://download.clever-vpn.org/vpn-server/<TAG>/install.sh" >&2
    exit 1
fi

# TAG 会被拼进 URL（与 install.sh 里同一口径的白名单），顺序：主源 → 发布镜像 → 历史位置
SOURCES=(
    "R2|https://download.clever-vpn.org/vpn-server/$TAG"
    "GitHub release|https://github.com/clever-vpn/clever-vpn-server/releases/download/$TAG"
    "GitHub raw|https://github.com/clever-vpn/clever-vpn-server/raw/$TAG"
)

for entry in "${SOURCES[@]}"; do
    label="${entry%%|*}"
    base="${entry#*|}"
    if script="$(curl -fsSL --connect-timeout 10 --max-time 60 "$base/install.sh" 2>/dev/null)"; then
        if [[ "$script" == *"CLEVER_VPN_INSTALL_SHIM=1"* ]]; then
            echo "WARNING: $label serves this shim itself; trying the next source." >&2
            continue
        fi
        echo "Fetching the installer for $TAG from $label..." >&2
        # 原样传递参数："$0" 是调用方给的位置占位符（生产里是 "@"），"$@" 是 <TAG> [TOKEN]
        exec bash -c "$script" "$0" "$@"
    fi
done

echo "ERROR: could not fetch install.sh for $TAG from any source." >&2
echo "       Checked: R2 mirror, GitHub release assets, and the historical raw/<TAG> path." >&2
exit 1
