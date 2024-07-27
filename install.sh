#!/usr/bin/env bash

# Usage:
# ./install.sh install [token]
# ./install.sh activate token
# ./install.sh remove

set -e -o pipefail
shopt -s extglob

YES=""
NO_CONFIRM=""
SERVER_NAME="clever-vpn-server"
SERVER_TOOL="clever-vpn"
INSTALLER="/usr/bin/${SERVER_TOOL}"

user_input() {
  local prompt="$1" # 获取提示信息
  local answer      # 用于存储用户的输入

  if [[ "$YES" == "-y" ]]; then
    return 0
  fi

  while true; do
    # 提示用户输入
    read -p "$prompt [y/N] " answer

    # 将用户输入转换为小写以便比较
    # answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')

    # 检查用户的输入并返回相应的状态
    case "$answer" in
    yes | y)
      return 0 # 返回 0 表示 'yes'
      ;;
    No | N)
      return 1 # 返回 1 表示 'no'
      ;;
    *)
      echo "Invalid input. Please enter 'y' or 'N'."
      # 继续循环，提示用户重新输入
      ;;
    esac
  done
}

get_token() {
  # 定义文件路径
  token_path="/etc/clever-vpn-server/token"

  # 检查文件是否存在
  if [ -f "$token_path" ]; then
    # 如果文件存在，读取文件内容
    token=$(cat "$token_path")
  else
    # 如果文件不存在，将内容设置为空
    token=""
  fi

  # 输出文件内容（或空内容）
  echo "$token"
}

function isRoot() {
  if [ "${EUID}" -ne 0 ]; then
    echo "You need to run this script as root !"
    return 1
  fi
}

function checkVirt() {
  if [ "$(systemd-detect-virt)" == "openvz" ]; then
    echo "OpenVZ is not supported !"
    return 1
  fi

  if [ "$(systemd-detect-virt)" == "lxc" ]; then
    echo "LXC is not supported (yet) !"
    return 1
  fi
}

# install_pkg pkg-index : 0: basic utils (tar);  1 toolchain; 2: linux-headers
install_pkg() {
  index=$1
  source /etc/os-release
  case ${ID} in
  ubuntu | debian) {
    case $index in
    0)
      apt-get update
      apt-get install $YES tar
      ;;
    # 1) apt-get install $YES build-essential ;;
    1)
      apt-get update
      apt-get install $YES make gcc
      ;;
    2)
      apt-get install $YES linux-headers-$(uname -r)
      ;;
    esac
  } ;;
  fedora | oracle) {
    case $index in
    0)
      dnf install $YES tar
      ;;
    # 1) dnf groupinstall $YES "Development Tools" ;;
    1)
      dnf install $YES make gcc
      ;;
    2)
      dnf install $YES kernel-devel-$(uname -r)
      ;;
    esac
  } ;;
  centos | almalinux | rocky) {
    case $index in
    0)
      yum install $YES tar
      ;;
    # 1) yum groupinstall $YES "Development Tools" ;;
    1) yum install $YES make gcc ;;
    2) yum install $YES kernel-devel-$(uname -r) ;;
    esac

  } ;;
  arch) {
    case $index in
    0)
      pacman -Sy
      pacman -S --needed $NO_CONFIRM tar
      ;;
    # 1) pacman -S --needed --noconfirm base-devel ;;
    1)
      pacman -Sy
      pacman -S --needed $NO_CONFIRM make gcc
      ;;
    2) pacman -S --needed $NO_CONFIRM linux-headers ;;
    esac

  } ;;
  *) {
    error "command not support"
    exit 1
  } ;;
  esac
}

function checkOS() {
  ## kernel >= 5.6
  required_major=5
  required_minor=6
  read -r current_major current_minor _ <<<"$(uname -r | tr '.' ' ')"

  if ((current_major < required_major)) || ((current_major == required_major && current_minor < required_minor)); then
    echo "Current Kernel version is $(uname -r). We need kernel version >= $required_major.$required_minor ! "
    return 1
  fi

  ## support systemd
  if ! pgrep systemd >/dev/null 2>&1; then
    echo "Current Linux don't support systemd. We only support linux version with systemd!"
    return 1
  fi

  # include tar enviroment
  if ! command -v "tar" >/dev/null 2>&1; then
    echo "Dont include tar  tools!"
    if user_input "Do you want to install  tar  tool"; then
      install_pkg 0
    else
      return 1
    fi
  fi

  # include make enviroment
  if ! command -v "make" >/dev/null 2>&1; then
    echo "Dont include toolchain。We need toolchain for compile kernel module!"
    if user_input "Do you want to install toolchain"; then
      install_pkg 1
    else
      return 1
    fi
  fi

  ## support kernel modules
  if [[ ! -e "/lib/modules/$(uname -r)/build" ]]; then
    echo "Don't include kernel-devel! We need linux-kernel for compile kernel module!"
    if user_input "Do you want to install kernel-devel"; then
      install_pkg 2
    else
      return 1
    fi
  fi

  if [[ ! -e "/lib/modules/$(uname -r)/build" ]]; then
    echo "Don't find kernel-devel of current kernel version $(uname -r)! Maybe you need to update your kernel for it!"
    return 1
  fi

}

function initialCheck() {
  if isRoot && checkVirt && checkOS; then
    return 0
  else
    return 1
  fi
}

curl() {
  $(type -P curl) -L -q --retry 5 --retry-delay 10 --retry-max-time 60 "$@"
}

#  "Usage: $0 [owner] [repo] [tag] [name] [token]"
getGithubRelease() {
  read owner repo tag name token <<<$@
  # Define variables.
  GH_API="https://api.github.com"
  GH_REPO="$GH_API/repos/$owner/$repo"
  if [ "$tag" == "latest" ]; then
    GH_TAGS="$GH_REPO/releases/latest"
  else
    GH_TAGS="$GH_REPO/releases/tags/$tag"
  fi

  if [ -z "$token" ]; then
    AUTH=""
  else
    AUTH="Authorization: token $token"
  fi
  CURL_ARGS="-LJO#"

  # Validate token.
  curl -o /dev/null -sH "$AUTH" $GH_REPO || {
    echo "Error: Invalid repo, token or network issue!"
    exit 1
  }
  # Read asset tags.
  response=$(curl -sH "$AUTH" $GH_TAGS)
  # Get ID of the asset based on given name.
  eval $(echo "$response" | grep -C3 "name.:.\+$name" | grep -w id | tr : = | tr -cd '[[:alnum:]]=')
  #id=$(echo "$response" | jq --arg name "$name" '.assets[] | select(.name == $name).id') # If jq is installed, this can be used instead.
  [ "$id" ] || {
    echo "Error: Failed to get asset id, response: $response" | awk 'length($0)<100' >&2
    exit 1
  }
  GH_ASSET="$GH_REPO/releases/assets/$id"
  # Remove file of name from this current dir
  rm -f "$name"
  # Download asset file.
  echo "Downloading asset..."
  curl $CURL_ARGS -H "$AUTH" -H 'Accept: application/octet-stream' "$GH_ASSET"
}

install() {

  getGithubRelease "clever-vpn" "${SERVER_NAME}" "latest" "${SERVER_NAME}.tar.gz" ""

  echo "Installing..."

  tar -xzf ${SERVER_NAME}.tar.gz
  if ${SERVER_NAME}${INSTALLER} "install" "$(pwd)/${SERVER_NAME}" $1; then
    code=0
  else
    code=1
  fi

  rm -rf ${SERVER_NAME} ${SERVER_NAME}.tar.gz

  return $code
}

uninstall() {
  if [[ -e ${INSTALLER} ]]; then
    ${INSTALLER} "uninstall"
  else
    echo "Clever vpn server is not exist. Please install first!"
    return 1
  fi
}

activate() {
  if [[ -n $1 ]]; then
    if [[ -e ${INSTALLER} ]]; then
      ${INSTALLER} "activate" $1
    else
      echo "Clever vpn server is not exist. Please install first!"
      return 1
    fi
  else
    echo "error: no token"
    return 1
  fi
}

help() {
  echo "Usage:"
  echo "installer install  [token]"
  echo "installer install_y  [token]"
  echo "installer uninstall"
  echo "installer help"
}

main() {

  # cd # change to root home
  cd /root
  if [[ $# -ge 1 ]]; then
    {
      case $1 in
      install_y) {
        YES="-y"
        NO_CONFIRM="--noconfirm"
      } ;&
      install) {
        shift
        echo "Installing ..."

        if ! initialCheck; then
          echo "Errror: Clever VPN Server installation failed! Contact us by Web chat"
          exit 1
        fi

        token=${1:-$(get_token)}

        uninstall || :
        # if install $@; then
        if install $token; then
          echo "Clever VPN Server is installed successly! Congratulation!"
        else
          echo "Errror: Clever VPN Server installation failed! Contact us by Web chat  "
        fi
      } ;;
      *)
        help
        ;;
      esac
    }
  else
    help
  fi

}

main "$@"
