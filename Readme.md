# Clever-VPN-Server: Linux kernel-based VPN Server

It is VPN server software that implements the Clever VPN protocol in the Linux kernel. Due to the kernelization of the VPN protocol, it efficiently adapts to dynamic changes, resulting in powerful anti-packet inspection capabilities. It operates 365 days a year, ensuring seamless access even on special dates. 

Please visist https://www.clever-vpn.net for more information.

## Why Clever VPN?

[![](/images/why-clever-vpn.png)](https://www.clever-vpn.net)

## Basic Usage

**Install & Upgrade**
- Install Clever-VPN-Server
  visit https://www.clever-vpn.net to create a server. you can get install script with token.  
```
bash -c "$(curl -L https://github.com/clever-vpn/clever-vpn-server/raw/main/install.sh)" @ install
```
- Activate <br/>
  visit https://www.clever-vpn.net to create a server. you can get a token of activate
```
clever-vpn activate [token]
```
**Check the Server Status**

```
clever-vpn status
```

**Remove**

```
clever-vpn uninstall
```

## system requirements: 
- Linux kernel version 5.6 or higher;
- Linux OS supports systemd services.

## List of Verified Supported Linux Distributions
- Ubuntu
- Debian
- CentOS
- Red Hat Enterprise Linux (RHEL)
- Fedora
- OpenSUSE
- almalinux
- rocky
- Arch Linux
- Kali Linux
- Oracle

## List of Unsupported Linux Distributions
- Alpine Linux
- Gentoo
- Slackware

## FAQ
### How to resolve installation error： "Don't find kernel-devel of current kernel version x.x.x-xxx! Maybe you need to update your kernel for it!"
Clever-VPN-Server服务器在运行时，需要编译vpn协议内核模块，它需要linux内核模块编译环境。这个环境存放在/lib/modules/$(uname -r)/build目录下。如果这个目录不存在或者是空，则表示它没有当前内核模块编译环境。正常情况下，安装程序在跟您确认后，会自动安装。有时，安装时找不到与当前内核匹配的内核模块编译环境，这是因为内核版本较老，发行厂商的软件仓库不再提供造成的。遇到这种情况，应该升级你的内核，重新启动服务器，再进行安装。

Clever-VPN-Server server requires the VPN protocol kernel module to be compiled while running, and it needs the Linux kernel module compilation environment. This environment is stored in the /lib/modules/$(uname -r)/build directory. If this directory does not exist or is empty, it indicates that the current kernel module compilation environment is not present. Normally, the installer will automatically install it after confirming with you. Sometimes, the installer cannot find the kernel module compilation environment that matches the current kernel. This is because the kernel version is too old, and the software repository from the distribution vendor no longer provides it. In such cases, you should upgrade your kernel, reboot the server, and then proceed with the installation.

### 内核升级方法
- apt
  ```
  sudo apt update
  sudo apt install linux-image
  sudo reboot
  ```
- dnf/yum
  ```
  sudo dnf refresh
  sudo dnf install kernel
  sudo reboot
  ```
- pacman
  ```
  sudo pacman -Syu
  sudo pacman -S linux
  sudo reboot
  ```
- zypper
  ```
  sudo zypper refresh
  sudo zypper install  kernel-default
  sudo reboot
  ```
