---
layout: post
title: "Configure Route-based IPsec VPN in an Ubuntu VM using strongSwan"
author: Sriram H. Iyer
---

## Table of Contents
- [Overview](#overview)
- [Network Architecture](#network-architecture)
- [Enable IP forwarding](#enable-ip-forwarding)
- [Configuring strongSwan](#configuring-strongswan)
- [Verification of IPsec](#verification-of-ipsec)

## Overview

In this blob, we will configure route-based IPsec VPN in an Ubuntu VM using [strongSwan](https://docs.strongswan.org/docs/5.9/howtos/introduction.html) package.

## Network Architecture

Before we configure IPsec VPN using strongSwan, we need to deploy Azure VMs with Public IPs which are in different VNets and there is no connecitivity between VNets in any manner. You could perform this excerise in AWS as well by creating two EC2 instances in different VPCs.

![network-diagram](https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/main/_pictures/strongSwan-network-diagram.png)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fhisriram1996%2Fhisriram1996.github.io%2Frefs%2Fheads%2Fmain%2F_arm-templates%2FstrongSwan-azure-deployment.json)

Azure CLI commands for deploying a similar setup.

```bash
read -p "Enter the username of the VM: " username
read -s -p "Enter the password of the VM: " password
read -p "Enter the resource group: " rg
read -p "Enter the region: " region
read -s -p "Enter the pre-shared key for the VPN: " psk
az group create --name $rg --location $region
az network public-ip create --name "test-vpnip" --resource-group $rg --location $region --allocation-method "Static" --sku "Standard" --zone 1 2 3
az network public-ip create --name "test-serverip" --resource-group $rg --location $region --allocation-method "Static" --sku "Standard" --zone 1 2 3
az network public-ip create --name "test-bastionip" --resource-group $rg --location $region --allocation-method "Static" --sku "Standard" --zone 1 2 3
az network asg create --name "test-asg" --resource-group $rg --location $region
az network nsg create --name "test-nsg" --resource-group $rg --location $region
az network nsg rule create --name "AllowVPN" --nsg-name "test-nsg" --resource-group $rg --priority 500 --access "Allow" --direction "Inbound" --protocol "Udp" --source-address-prefixes $(az network public-ip show --name "test-vpnip" --resource-group $rg --query "ipAddress" -o tsv) --source-port-ranges "*" --destination-asgs "test-asg" --destination-port-ranges 500 4500
az network vnet create --name "test-vnet" --resource-group $rg --location $region --address-prefix "192.168.1.0/24"
az network vnet create --name "test-datacenter" --resource-group $rg --location $region --address-prefix "192.168.2.0/24"
az network vnet subnet create --name "vm-subnet" --vnet-name "test-vnet" --resource-group $rg --address-prefixes "192.168.1.0/27" --network-security-group "test-nsg"
az network vnet subnet create --name "GatewaySubnet" --vnet-name "test-vnet" --resource-group $rg --address-prefixes "192.168.1.32/27"
az network vnet subnet create --name "server-subnet" --vnet-name "test-datacenter" --resource-group $rg --address-prefixes "192.168.2.0/26" --network-security-group "test-nsg"
az network vnet subnet create --name "AzureBastionSubnet" --vnet-name "test-datacenter" --resource-group $rg --address-prefixes "192.168.2.64/26"
az network nic create --name "vm-nic" --resource-group $rg --location $region --subnet "vm-subnet" --vnet-name "test-vnet" --private-ip-address "192.168.1.4"
az network nic create --name "server-nic" --resource-group $rg --location $region --subnet "server-subnet" --vnet-name "test-datacenter" --private-ip-address "192.168.2.4" --ip-forwarding "true" --public-ip-address "test-serverip" --application-security-groups "test-asg"
az vm create --name "test-vm" --resource-group $rg --location $region --image "canonical:ubuntu-24_04-lts:server:latest" --size "Standard_D2as_v4" --os-disk-name "vm-disk" --nics "vm-nic" --authentication-type "password" --admin-username $username --admin-password $password
az vm create --name "test-server" --resource-group $rg --location $region --image "canonical:ubuntu-24_04-lts:server:latest" --size "Standard_D2as_v4" --os-disk-name "server-disk" --nics "server-nic" --authentication-type "password" --admin-username $username --admin-password $password
az network bastion create --name "test-bastion" --resource-group $rg --vnet-name "test-datacenter" --sku Standard --public-ip-address "test-bastionip" --disable-copy-paste "false" --enable-ip-connect "true" --enable-tunneling "true" --file-copy "true"
az network vnet-gateway create --name "test-vpngateway" --resource-group $rg --vnet "test-vnet" --gateway-type "Vpn" --sku "VpnGw1AZ" --public-ip-address "test-vpnip"
az network local-gateway create --name "test-localgateway" --resource-group $rg --gateway-ip-address $(az network public-ip show --name "test-serverip" --resource-group $rg --query "ipAddress" -o tsv) --local-address-prefixes "192.168.2.0/24"
az network vpn-connection create --name "test-vpnconnection" --resource-group $rg --vnet-gateway1 "test-vpngateway" --local-gateway2 "test-localgateway" --shared-key $psk
```

## Enable IP forwarding

In Ubuntu distros, you could enable IP forwarding by modifying the contents of ```/etc/sysctl.conf```. One of the easy way to do it is by using ```sed``` command as below.

```bash
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
sudo sed -i 's/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/g' /etc/sysctl.conf
sudo sysctl -p
```

Example:

<img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/main/_pictures/_images_2023-12-13-strongSwan-IPsec/image1.png">

Since we deployed Azure VMs, we must also enable IP forwarding in the vNIC of the Azure VMs.

Please note that enabling IP forwarding in the vNIC of the Azure VM is an additional step as it does not enable IP forwarding in the guest OS so we still need to enable IP forwarding in Ubuntu OS.

<img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/main/_pictures/_images_2023-12-13-strongSwan-IPsec/image2.png">

## Configuring strongSwan

With our network infrastructure ready and IP forwarding enabled in the OS and in VNIC, we could proceed with the configuration of IPsec VPN.

1. Install strongSwan.

   ```bash
   sudo apt-get update
   sudo apt-get install strongswan strongswan-pki libstrongswan-extra-plugins -y
   ```

2. Create a network namespace and VTI interface.

   ```bash
   sudo ip netns add vpn
   sudo ip tunnel add vti0 local Private_IP_address_of_the_VM remote <VPN_peer_public_IP_address> mode vti key 42
   sudo sysctl -w net.ipv4.conf.vti0.disable_policy=1
   sudo ip link set vti0 netns vpn
   sudo ip -n vpn link set vti0 up
   ```

   Example:

   <img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_pictures/_images_2026-07-05-strongSwan-IPsec-route-based-vpn/image1.png">

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
         mark=42
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

   > The `mark` value of a conn must be identical to the `key` value of its corresponding VTI interface. If multiple VPN tunnels are configured, each `conn` must use a unique mark value that matches the key value of its associated VTI interface and each VTI must be in its corresponding network namespace.
   
   Example:

   <img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_pictures/_images_2026-07-05-strongSwan-IPsec-route-based-vpn/image2.png">

5. Configure pre-shared key for VPN in ipsec.secrets file.

   ```bash
   sudo vi /etc/ipsec.secrets
   ```

   Contents of the ```ipsec.secrets``` file.

   ```bash
   <Private_IP_address_of_the_VM> <VPN_peer_IP_address> : PSK "<pre-shared_key>"
   ```

   Please make sure that the same pre-shared key is configured on both IPsec peers. Otherwise, VPN will be down.

7. Restart the strongSwan process.

   ```bash
   sudo systemctl restart ipsec
   sudo systemctl status ipsec
   ```

   Example:

   <img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_pictures/_images_2026-07-05-strongSwan-IPsec-route-based-vpn/image3.png">

## Verification of IPsec

You could verify if the IPsec is established by executing the command ```sudo ipsec status```.

You could perform stop and start operations using command ```sudo ipsec stop``` and started using ```sudo ipsec start``` commands. Please refer to the [man page](https://manpages.ubuntu.com/manpages/noble/en/man8/ipsec.8.html) of ```ipsec``` command.

In case the IPsec doess not establish, you could troubleshoot with the help of IPsec logs by using the command below.

```bash
sudo cat /var/log/syslog | grep "ipsec"
```

<link rel="alternate" type="application/rss+xml"  href="{{ site.url }}/feed.xml" title="{{ site.title }}">
