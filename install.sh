#!/usr/bin/env bash

# Usage:
# ./install.sh install [key]
# ./install.sh activate key
# ./install.sh remove

set -e -o pipefail
shopt -s extglob

SERVER_NAME="clever-vpn-server"
INSTALLER="/usr/bin/${SERVER_NAME}/installer"

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
  if ! pgrep systemd; then
    echo "Current Linux don't support systemd. We only support linux version with systemd!"
    return 1
  fi
   
  ## support kernel modules 
  if [[ ! -d "/lib/modules/$(uname -r)" ]]; then
    echo "Don't include kernel modules! We need linux-kernel-header for compile kernel module!"
    return 1
  fi

  ## include make enviroment
  if ! command -v "make" >/dev/null 2>&1; then
    echo "Dont include toolchain。We need toolchain for compile kernel module!"
    return 1
  fi

}

# function checkOS() {
#   source /etc/os-release
#   OS="${ID}"
#   if [[ ${OS} == "debian" || ${OS} == "raspbian" ]]; then
#     if [[ ${VERSION_ID} -lt 10 ]]; then
#       echo "Your version of Debian (${VERSION_ID}) is not supported. Please use Debian 10 Buster or later"
#       exit 1
#     fi
#     OS=debian # overwrite if raspbian
#   elif [[ ${OS} == "ubuntu" ]]; then
#     RELEASE_YEAR=$(echo "${VERSION_ID}" | cut -d'.' -f1)
#     if [[ ${RELEASE_YEAR} -lt 18 ]]; then
#       echo "Your version of Ubuntu (${VERSION_ID}) is not supported. Please use Ubuntu 18.04 or later"
#       exit 1
#     fi
#   elif [[ ${OS} == "fedora" ]]; then
#     if [[ ${VERSION_ID} -lt 32 ]]; then
#       echo "Your version of Fedora (${VERSION_ID}) is not supported. Please use Fedora 32 or later"
#       exit 1
#     fi
#   elif [[ ${OS} == 'centos' ]] || [[ ${OS} == 'almalinux' ]] || [[ ${OS} == 'rocky' ]]; then
#     if [[ ${VERSION_ID} == 7* ]]; then
#       echo "Your version of CentOS (${VERSION_ID}) is not supported. Please use CentOS 8 or later"
#       exit 1
#     fi
#   elif [[ -e /etc/oracle-release ]]; then
#     source /etc/os-release
#     OS=oracle
#   elif [[ -e /etc/arch-release ]]; then
#     OS=arch
#   else
#     echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS, AlmaLinux, Oracle or Arch Linux system"
#     exit 1
#   fi
# }

function initialCheck() {
  if isRoot && checkVirt && checkOS ; then 
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
  echo "Downloading asset..." >&2
  curl $CURL_ARGS -H "$AUTH" -H 'Accept: application/octet-stream' "$GH_ASSET"
}

install() {

  getGithubRelease "wireguard-vpn" "${SERVER_NAME}" "latest" "${SERVER_NAME}.tar.gz" ""
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
    echo "error: no key"
    return 1
  fi
}

help() {
  echo "Usage:"
  echo "installer install  [key]"
  echo "installer uninstall"
  echo "installer activate key"
  echo "installer help"
}

main() {
  if ! initialCheck; then
    echo "Errror: Clever VPN Server installation failed! Contact us by Web chat"
    exit 1
  fi
  # cd # change to root home
  cd /root
  if [[ $# -ge 1 ]]; then
    {
      case $1 in
      install) {
        shift
        uninstall || :
        if install $@; then
          echo "Clever VPN Server is installed successly! Congratulation!"
        else
          echo "Errror: Clever VPN Server installation failed! Contact us by Web chat  "
        fi
      } ;;
      uninstall) {
        shift
        if uninstall $@; then
          echo "Clever VPN Server is uninstalled successly!"
        else
          echo "Errror: Clever VPN Server uninstallation failed!"
        fi
      } ;;
      activate) {
        shift
        if activate $@; then
          echo "Clever VPN Server is activated successly!"
        else
          echo "Errror: Clever VPN Server activation failed! Contact us by Web chat"
        fi
      } ;;
      help) {
        help
      } ;;
      *)
        error "$1 command not support"
        ;;
      esac
    }
  else
    error "no command"
  fi

}

main "$@"
