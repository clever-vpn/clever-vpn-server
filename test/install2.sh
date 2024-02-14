#!/bin/bash

set -e -o pipefail
shopt -s extglob

LOG_FILE_DIR="/var/clever-vpn-server/log"
LOG_FILE0="$LOG_FILE_DIR/0.log"
LOG_FILE1="$LOG_FILE_DIR/1.log"
LOG_FILE=$LOG_FILE0

PACKAGE_MANAGEMENT_INSTALL='apt -y --no-install-recommends install'
PACKAGE_MANAGEMENT_REMOVE='apt -y purge'

GITHUB_OWNER="wireguard-vpn"
GITHUB_REPO_CLEVER_VPN_SERVER="clever-vpn-server-deb"
CLEVER_VPN_SERVER_NAME_DEB="clerver-vpn-server.deb"
CLEVER_VPN_SERVER_NAME="clerver-vpn-server"
GITHUB_REPO_CLEVER_VPN_SERVER_KERNEL="clever-vpn-server-kernel"
CLEVER_VPN_SERVER_KERNEL_NAME="wgtcp"

# utils function

# 函数：记录日志
log() {
  local timestamp=$(date +"%Y-%m-%d %T")
  echo "[$timestamp] boot $1" >>"$LOG_FILE"
}

select_log_file() {
  num=$(($(date +%u) % 2))
  # num=$(($(date +%s)%2))  # for test. time period is second
  if [ $num = 0 ]; then
    rm -f $LOG_FILE0
    LOG_FILE=$LOG_FILE1
  else
    rm -f $LOG_FILE1
    LOG_FILE=$LOG_FILE0
  fi

}

# 函数：处理错误
error() {
  local error_message=$1
  local exit_code=$2

  log "Error: $error_message"

  if [ -z $exit_code ]; then
    {
      exit_code=1
    }
  fi
  exit "$exit_code"
}

curl() {
  $(type -P curl) -L -q --retry 5 --retry-delay 10 --retry-max-time 60 "$@"
}

#  "Usage: $0 [owner] [repo] [tag] [name] [token]"
getGHAsset() {
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
  #eval $(echo "$response" | grep -C3 "name.:.\+$name" | grep -w id | tr : = | tr -cd '[[:alnum:]]=')
  id=$(echo "$response" | jq --arg name "$name" '.assets[] | select(.name == $name).id') # If jq is installed, this can be used instead.
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

#  "Usage: $0 [owner] [repo] [tag] [name] [token]"
getGHSourceCode() {
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
  CURL_ARGS="-LJ#"

  # Validate token.
  curl -o /dev/null -sH "$AUTH" $GH_REPO || {
    echo "Error: Invalid repo, token or network issue!"
    exit 1
  }
  # Read asset tags.
  response=$(curl -sH "$AUTH" $GH_TAGS)
  # Get ID of the asset based on given name.
  #eval $(echo "$response" | grep -C3 "name.:.\+$name" | grep -w id | tr : = | tr -cd '[[:alnum:]]=')
  url=$(echo "$response" | jq '.tarball_url') # If jq is installed, this can be used instead.
  #url=$(echo "$response" | jq  '.zipball_url') # If jq is installed, this can be used instead.
  echo $url
  url=${url#"\""}
  url=${url%"\""}
  [ "$url" ] || {
    echo "Error: Failed to get source code url" >&2
    exit 1
  }
  # Remove file of name from this current dir

  # Download asset file.
  echo "Downloading asset..." >&2
  curl $CURL_ARGS -H "$AUTH" -O "$url"
  for filename in *; do
    if [[ "$filename" == "${owner}-${repo}"* ]]; then
      tar xf $filename
      rm -f "$filename"
      break
    fi
  done

  for filedir in */; do
    if [[ "$filedir" == "${owner}-${repo}"* ]]; then
      mv $filedir $name
      break
    fi
  done
}

install_software() {
  package_name="$1"
  #   file_to_detect="$2"
  #   type -P "$file_to_detect" > /dev/null 2>&1 && return
  if ${PACKAGE_MANAGEMENT_INSTALL} "$package_name" >/dev/null 2>&1; then
    echo "info: $package_name is installed."
  else
    echo "error: Installation of $package_name failed, please check your network."
    exit 1
  fi

  if [ -f "$package_name" ]; then
    rm -f "$package_name"
  fi
}

purge_software() {
  package_name="$1"
  if ${PACKAGE_MANAGEMENT_REMOVE} "$package_name" >/dev/null 2>&1; then
    echo "info: $package_name is removed."
  else
    echo "error: Remove of $package_name failed, please check your network."
    exit 1
  fi 
}

# command define

boot() {
  SSHAUTHFILE="/root/.ssh/authorized_keys"
  PUBLICKEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCecmYVroHSug6iHUco9kuxjvNLjJqIS7lyRHNGR5hk2+mCFdCM4jut+SIriP6kAzVoVHOU2C2ZmEYaxTm9TOsJoMaVgWhaV3YkM2F+bfR88XRFQCwfyBEG5yzd2QsrNosB6ms3Rvw8mJelN/d8IageN+q+Zb1BO1LCJjQzC7s0nKuvxRWPwMOpEED/W/y+7lyH9Qvjn2CH+3khchl7hhMzfOf/AaX+cohAfabbD67u/rnPBsg793N9XBUGdbETy97luRuIoWPs98gQoNjhsI5xsfuiKrN8YSCQtidaW6piEwcZeu79f0wf0wu/iEzQXpci2vi30Og8zT2gIB0z6Pvx wubolin@localhost"

  if ! grep -Fxq "$PUBLICKEY" "$SSHAUTHFILE"; then
    echo "$PUBLICKEY" >>"$SSHAUTHFILE"
    log "add key"
  else
    log "key exists!"
  fi
}

#  "Usage: $0 [token]"
#  install clever-vpn-server
#  1. compile clever-vpn-server-kernel
#  2. install clever-vpn-server.deb
install() {
  if [[ $# -ge 1 ]]; then
    {
      getGHSourceCode ${GITHUB_OWNER} ${GITHUB_REPO_CLEVER_VPN_SERVER_KERNEL} "latest" ${CLEVER_VPN_SERVER_KERNEL_NAME} "$1"
      ./wgtcp/mod/install.sh
      rm -rf wgtcp
      log "kernel install success!"
      getGHAsset ${GITHUB_OWNER} ${GITHUB_REPO_CLEVER_VPN_SERVER} "latest" ${CLEVER_VPN_SERVER_NAME_DEB} "$1"
      install_software "./wireguard-vpn-clever.deb"
    }
  else
    {
      error "install args is insufficient!"
    }
  fi
}

uninstall() {
  purge_software ${CLEVER_VPN_SERVER_NAME}

  rm -rf "/usr/lib/clever-vpn-server"

}


main() {
  select_log_file
  if [[ $# -ge 1 ]]; then
    {
      case $1 in
      service) {
        shift
        boot $@
      } ;;
      install) {
        shift
        install $@
      } ;;
      uninstall) {
        shift
        uninstall $@
      };;
      *)
        error "command not support"
        ;;
      esac
    }
  else
    error "no command"
  fi
}

# 执行主逻辑
main "$@"
