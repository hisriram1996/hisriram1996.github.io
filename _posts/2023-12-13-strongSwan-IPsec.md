---
layout: post
title: "Configure IPsec VPN in an Ubuntu VM using strongSwan"
author: Sriram H. Iyer
---

## What is strongSwan?

[strongSwan](https://docs.strongswan.org/docs/5.9/howtos/introduction.html) is an open-source package for IPsec VPN. You could use strongSwan for configuring VPN in Linux, UNIX, and BSD Operating Systems.

In this example, we will configure an IPsec VPN in an Ubuntu VM. However, same configuration can be applied for RedHat and other distos.

Please note that the IPsec VPN is setup between an Azure VM and Azure Virtual Network Gateway which are in different VNets and there is no connecitivity between VNets in any manner. So, before proceeding with rest of the Blog, please create Azure VMs and Virtual Network Gateway in different VNets with public IPs. You could perform this excerise in AWS as well by creating EC2 instances and Virtual Private Gateway in different VPCs.

## Network Architecture

Before we configure IPsec VPN using strongSwan, we need to deploy Azure VMs with Public IPs which are in different VNets and there is no connecitivity between VNets in any manner. You could perform this excerise in AWS as well by creating two EC2 instances in different VPCs.

![network-diagram](https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/main/_pictures/strongSwan-network-diagram.png)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fhisriram1996%2Fhisriram1996.github.io%2Frefs%2Fheads%2Fmain%2F_arm-templates%2FstrongSwan-azure-deployment.json)

## Enable IP forwarding

Before configuring IPsec VPN, we must make sure that our VMs act as routers.

Router can accept and forward packets which are not destined to itself. This behaviour of router is called *IP forwarding*. However, servers/VMs would discard the packets which have destination IP differnt from the its own.

This is default behaviour for servers/VMs and we can change it. We can configure the OS of the server/VM to accept the packets which have destination IP differnt from the its own interface IP. This configuration differs depending on the OS.

In Ubuntu distros, you could enable IP forwarding by modifying the contents of ```/etc/sysctl.conf```. One of the easy way to do it is by using ```sed``` command as below.

```bash
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
sudo sed -i 's/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/g' /etc/sysctl.conf
sudo sysctl -p
```

Example:

<img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/1fc3beec3c7d26552ab6f5cdadbc162949118a11/_pictures/_images_2023-12-13-strongSwan-IPsec/image1.png">

Since we deployed Azure VMs, we must also enable IP forwarding in the vNIC of the Azure VMs.

Please note that enabling IP forwarding in the vNIC of the Azure VM is an additional step as it does not enable IP forwarding in the guest OS so we still need to enable IP forwarding in Ubuntu OS.

<img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/1fc3beec3c7d26552ab6f5cdadbc162949118a11/_pictures/_images_2023-12-13-strongSwan-IPsec/image2.png">

## Configuring strongSwan

With our network infrastructure ready and IP forwarding enabled in the OS and in VNIC, we could proceed with the configuration of IPsec VPN.

1. Install strongSwan.

   ```bash
   sudo apt-get update
   sudo apt-get install strongswan -y
   sudo apt-get install strongswan-pki -y
   sudo apt-get install libstrongswan-extra-plugins -y
   ```

   Example:
   
   <img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/1fc3beec3c7d26552ab6f5cdadbc162949118a11/_pictures/_images_2023-12-13-strongSwan-IPsec/image3.png">

3. Configure IPsec VPN by editing the ipsec.conf file.

   ```bash
   sudo vi /etc/ipsec.conf
   ```

   Contents of the ```ipsec.conf``` file.

   ```bash
   config setup
		   charondebug="all"
		   uniqueids=yes
   conn tunnel21
		   type=tunnel
		   left=<Private_IP_address_of_the_VM>
		   leftsubnet=<Local_IP_prefix>
		   right=<VPN_peer_IP_address>
		   rightsubnet=<Remote_IP_prefix>
		   keyexchange=ikev2
		   keyingtries=%forever
		   authby=psk
		   ike=aes256-sha256-modp1024!
		   esp=aes256-sha256!
		   keyingtries=%forever
		   auto=start
		   dpdaction=restart
		   dpddelay=45s
		   dpdtimeout=45s
		   ikelifetime=28800s
		   lifetime=27000s
		   lifebytes=102400000
   ```

   Example:

   <img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/1fc3beec3c7d26552ab6f5cdadbc162949118a11/_pictures/_images_2023-12-13-strongSwan-IPsec/image4.png">

5. Configure pre-shared key for VPN in ipsec.secrets file.

   ```bash
   sudo vi /etc/ipsec.secrets
   ```

   Contents of the ```ipsec.secrets``` file.

   ```bash
   <Private_IP_address_of_the_VM> <VPN_peer_IP_address> : PSK "<pre-shared_key>"
   ```

   Please make sure that the same pre-shared key is configured on both IPsec peers. Otherwise, VPN will be down.

   Example:

   <img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/1fc3beec3c7d26552ab6f5cdadbc162949118a11/_pictures/_images_2023-12-13-strongSwan-IPsec/image5.png">

7. Restart the strongSwan process.

   ```bash
   sudo systemctl restart ipsec
   sudo systemctl status ipsec
   ```

   Example:

   <img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/1fc3beec3c7d26552ab6f5cdadbc162949118a11/_pictures/_images_2023-12-13-strongSwan-IPsec/image6.png">

## Verification of IPsec

You could verify if the IPsec is established by executing the command ```sudo ipsec status```.

You could perform stop and start operations using command ```sudo ipsec stop``` and started using ```sudo ipsec start``` commands. Please refer to the [man page](https://manpages.ubuntu.com/manpages/noble/en/man8/ipsec.8.html) of ```ipsec``` command.

In case the IPsec doess not establish, you could troubleshoot with the help of IPsec logs by using the command below.

```bash
sudo cat /var/log/syslog | grep "ipsec"
```

<link rel="alternate" type="application/rss+xml"  href="{{ site.url }}/feed.xml" title="{{ site.title }}">
