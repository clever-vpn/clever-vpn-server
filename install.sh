#!/usr/bin/env bash


# install
INSTALL='0'
# remove
REMOVE='0'
# help
HELP='0'

PACKAGE_MANAGEMENT_INSTALL=''
PACKAGE_MANAGEMENT_REMOVE=''
BOOT_PKG="clever-vpn-server-boot"
BOOT_PKG_FILE="./$BOOT_PKG.deb"

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
    fi;

    if [ -z "$token" ]; then
        AUTH=""
    else
        AUTH="Authorization: token $token"
    fi;
    CURL_ARGS="-LJO#"

    # Validate token.
    curl -o /dev/null -sH "$AUTH" $GH_REPO || { echo "Error: Invalid repo, token or network issue!";  exit 1; }
    # Read asset tags.
    response=$(curl -sH "$AUTH" $GH_TAGS)
    # Get ID of the asset based on given name.
    eval $(echo "$response" | grep -C3 "name.:.\+$name" | grep -w id | tr : = | tr -cd '[[:alnum:]]=')
    #id=$(echo "$response" | jq --arg name "$name" '.assets[] | select(.name == $name).id') # If jq is installed, this can be used instead. 
    [ "$id" ] || { echo "Error: Failed to get asset id, response: $response" | awk 'length($0)<100' >&2; exit 1; }
    GH_ASSET="$GH_REPO/releases/assets/$id"
    # Remove file of name from this current dir
    rm -f "$name"
    # Download asset file.
    echo "Downloading asset..." >&2
    curl $CURL_ARGS -H "$AUTH" -H 'Accept: application/octet-stream'  "$GH_ASSET"
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

install() {
    getGithubRelease "wireguard-vpn" "clever-vpn-server-boot" "latest" "clever-vpn-server-boot.deb" ""
    install_software "$BOOT_PKG_FILE" 
}

remove() {
  purge_software   "$BOOT_PKG" 
}

help() {
    echo "help"
}

check_if_running_as_root() {
  # If you want to run as another user, please modify $EUID to be owned by this user
  if [[ "$EUID" -ne '0' ]]; then
    echo "error: You must run this script as root!"
    exit 1
  fi
}

identify_the_operating_system_and_architecture() {
  if [[ "$(uname)" != 'Linux' ]]; then
    echo "error: This operating system is not supported."
    exit 1
  fi
  case "$(uname -m)" in
    'amd64' | 'x86_64')
      MACHINE='64'
      ;;
    *)
      echo "error: The architecture is not supported."
      exit 1
      ;;
  esac
  if [[ ! -f '/etc/os-release' ]]; then
    echo "error: Don't use outdated Linux distributions."
    exit 1
  fi

  ## Be aware of Linux distribution like Gentoo, which kernel supports switch between Systemd and OpenRC.
  if [[ -d /run/systemd/system ]] || grep -q systemd <(ls -l /sbin/init); then
    true
  else
    echo "error: Only Linux distributions using systemd are supported."
    exit 1
  fi
  if [[ "$(type -P apt)" ]]; then
    PACKAGE_MANAGEMENT_INSTALL='apt -y --no-install-recommends install'
    PACKAGE_MANAGEMENT_REMOVE='apt -y purge'
  else
    echo "error: The script does not support the package manager in this operating system."
    exit 1
  fi
}

judgment_parameters() {
  local local_install='0'
  local temp_version='0'
  while [[ "$#" -gt '0' ]]; do
    case "$1" in
      'install')
        INSTALL='1'
        ;;
      'remove')
        REMOVE='1'
        ;;
      'help')
        HELP='1'
        ;;
      *)
        echo "$0: unknown option -- -"
        exit 1
        ;;
    esac
    shift
  done
}

main() {
  check_if_running_as_root
  identify_the_operating_system_and_architecture
  judgment_parameters "$@"

  if [[ "$INSTALL" -eq '1' ]]; then
    install
  elif [[ "$REMOVE" -eq '1' ]]; then
    remove
  else
    help
  fi;



}

main "$@"