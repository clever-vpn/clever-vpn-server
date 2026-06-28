#!/usr/bin/env bash
# ============================================================
# Packer provisioning script for clever-vpn-server
# Downloads the binary from GitHub Releases, verifies checksum,
# and installs it for DigitalOcean Kubernetes 1-Click App snapshot.
#
# Expected env vars:
#   APP_VERSION - version tag, e.g. v2.1.6
# ============================================================
set -euo pipefail

OWNER="clever-vpn"
REPO="clever-vpn-server"
APP="clever-vpn-server"

VERSION="${APP_VERSION:?APP_VERSION is required}"

echo "=== Installing clever-vpn-server ${VERSION} ==="

# ---- Detect architecture ----
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
echo "Detected architecture: $ARCH"

# ---- Download binary and checksum ----
BASE_URL="https://github.com/${OWNER}/${REPO}/releases/download/${VERSION}"
GZ="${APP}-${ARCH}-${VERSION}.gz"
SHA_FILE="${APP}-${ARCH}-${VERSION}.sha256"

echo "Downloading ${GZ}..."
curl -fsSL "${BASE_URL}/${GZ}" -o "${GZ}"

echo "Downloading ${SHA_FILE}..."
curl -fsSL "${BASE_URL}/${SHA_FILE}" -o "${SHA_FILE}"

# ---- Verify checksum ----
echo "Verifying checksum..."
sha256sum --check "${SHA_FILE}"
echo "Checksum OK."

# ---- Decompress ----
echo "Decompressing ${GZ}..."
gunzip -f "${GZ}"

# Normalize binary name (strip arch suffix)
DECOMPRESSED="${GZ%.gz}"
if [[ "${DECOMPRESSED}" != "${APP}" ]]; then
    mv -f "${DECOMPRESSED}" "${APP}"
fi

# ---- Install ----
echo "Running ${APP} install..."
chmod +x "${APP}"
./"${APP}" install

# ---- Verify installation ----
echo "Verifying installation..."
if command -v clever-vpn &>/dev/null; then
    clever-vpn status || true
    echo "clever-vpn-server ${VERSION} installed successfully."
else
    echo "ERROR: clever-vpn command not found after installation."
    exit 1
fi

# ---- Cleanup downloaded files ----
rm -f "${GZ}" "${SHA_FILE}" "${APP}"

echo "=== Installation complete ==="
