# Clever-VPN-Server install

Bash script for installing Clever VPN Server in operating systems that support deb package, such as debian\ubuntu ...

## Basic Usage

**Install & Upgrade**
- Install Clever-VPN-Server
```
bash -c "$(curl -L https://github.com/wireguard-vpn/clever-vpn-server-boot/raw/main/install.sh)" @ install
```
- Activate 
  visit https://www.clever-vpn.net to create a server. you can get a token of activate
```
clever-vpn activate [token]
```
**Remove**

```
bash -c "$(curl -L https://github.com/wireguard-vpn/clever-vpn-server-boot/raw/main/install.sh)" @ uninstall
```

