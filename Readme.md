# Clever-VPN-Server: Linux Kernel-based Clustered VPN Server

It is VPN server software that implements the Clever VPN protocol in the Linux kernel with clustering capabilities. Due to the kernelization of the VPN protocol and clustered deployment, it efficiently adapts to dynamic changes, resulting in powerful anti-packet inspection capabilities and high availability. It operates 365 days a year, ensuring seamless access even on special dates. 

Please visist [https://www.clever-vpn.net](https://www.clever-vpn.net) for more information.

## Why Us?

### Overview
With our SaaS based all‑in‑one VPN service platform, you don't need any technical background—you can become a professional VPN service provider in just 5 minutes and deliver enterprise‑grade VPN services to your users. We are the first cloud provider to offer a SaaS platform specifically for VPN service providers.

### Who are we?
We are a geek team of experts in the Linux kernel and VPN protocols. By deeply integrating VPN protocols into the Linux kernel and deploying servers in clustered form, we have dramatically improved our anti‑censorship capabilities and system stability. This solves the traditional VPN pain points of easy blocking and heavy maintenance burdens (especially frequent app updates to counter GFW blocking rules), making VPN‑as‑a‑Service a reality. As a VPN service provider using our platform, you will significantly reduce hardware investment, R&D and maintenance costs, and greatly boost operational efficiency.

Our philosophy: focus on core technology, deliver stable and reliable Software‑as‑a‑Service (SaaS), and eliminate redundant marketing and excess UI—true value driven by technology.

### What We Offer？
We provide a full-suite VPN service solution (SaaS):

<img src="https://clever-vpn.net/img/architecture.svg" alt="System Architecture" width="800"/>

#### 📱 APP Client - 🔓 **100% Open Source**
Users connect via our app, which features:
- All client source code is open source under MIT license, supporting customization and secondary development:
  - ![Apple](https://img.shields.io/badge/Apple-000000?style=flat&logo=apple&logoColor=white) **[Apple (iOS/macOS) Client](https://github.com/clever-vpn/clever-vpn-client-apple)** - Native iOS and macOS applications
  - ![Android](https://img.shields.io/badge/Android-3DDC84?style=flat&logo=android&logoColor=white) **[Android Client](https://github.com/clever-vpn/clever-vpn-client-android)** - Native Android application  
  - ![Windows](https://img.shields.io/badge/Windows-0078D4?style=flat&logo=windows&logoColor=white) **[Windows Client](https://github.com/clever-vpn/clever-vpn-client-windows)** - Native Windows application
- Configurable support/contact information can be managed in the backend, so your users always know how to reach you.
- Cross‑platform support (macOS, iOS, Android, Windows, etc.).

#### VPN Server Cluster Software
This is the VPN server software that implements the Clever VPN protocol and cluster management in the Linux kernel. It must be installed on your VPN servers. Key functions include:
- Coordination with the cloud management platform for intelligent cluster orchestration.
- Providing VPN connectivity services to the client apps.

#### VPN Service Cloud Platform (SaaS)
Key features:
- A management interface for VPN service providers to handle server clusters and user license management.
- License synchronization for VPN clients.
- VPN server cluster orchestration.
- API endpoints for integration with your CRM.

### How to use our services：
1. Log in to the VPN Service Cloud Platform at [https://www.clever-vpn.net](https://www.clever-vpn.net).
2. Create a VPN server. If you use our provided VPS, the VPN Server Cluster software will be installed automatically. If you use your own server, we guide you through a simple install script to get the software running.
3. Create user accounts on the cloud platform. Each account supports 1, 2, or 3 devices and is associated with a unique activation code.
4. Users download the appropriate app for their device and activate it using their account's activation code.
5. Once activated, the app is ready for use.

### Our Advantages

#### VPN Protocol Kernel Integration
We are the first VPN provider to implement the VPN protocol directly in the Linux kernel. Our solution is simpler, faster, and more adaptive than others. Kernel‑level innovation combined with cloud‑based operations drives an exponential reduction in operating costs and heralds a revolution in the industry.

#### VPN Server Clustering
Our proprietary clustered VPN server technology features intelligent routing, automatic load balancing, region‑based node management, and support for millions of users.

#### Standardized & Open‑Source Apps—No Updates Required
By moving all VPN protocol logic to the cloud, our VPN apps are standardized and no longer need constant updates to counter GFW block rules. All our client apps are open‑source on GitHub, enabling VPN service providers to white‑label and customize them without maintaining a large app development team.

#### Micro‑Sized VPN Servers
Since our VPN protocol runs in the Linux kernel, efficiency is greatly improved. You can become a VPN service provider with a small, low‑cost VPS for just a few dollars a month.

#### Unmatched Circumvention Capabilities
Kernel‑level implementation allows our VPN protocol to adapt dynamically to blocking tactics, delivering powerful anti‑detection abilities. Enjoy 365‑day uninterrupted access—even on sensitive dates, you can bypass censorship with ease.

#### Zero barriers
##### 1. Pay‑as‑You‑Go:
Hourly billing means you only pay for the VPN service when you use it—no usage, no charge.

##### 2. Monthly Billing:
Operate on a credit model—use now, pay later at month's end. Users enjoy a credit limit with zero risk of service disruption.

#### "Price Slayer"
We offer industry-leading low rates to our customers. It's just 1/10 of the industry standard. A license costs only $1/month.

## Basic Usage

**Install & Upgrade**
- Install Clever-VPN-Server
  visit https://www.clever-vpn.net to create a server. you can get install script with token.  
```
bash -c "$(curl -L https://github.com/clever-vpn/clever-vpn-server/raw/main/install.sh)" @ "v2.0.0"
```
- Activate <br/>
  visit https://www.clever-vpn.net to create a server. you can get a token of activate
```
clever-vpn activate -token=[token]
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

## One-click App of Cloud Provider Install
- Vultr: [https://www.vultr.com/marketplace/apps/clever-vpn](https://www.vultr.com/marketplace/apps/clever-vpn)

