---
layout: post
title: "Configure passive FTP in Azure VMs with high availability using Azure Load Balancer"
author: Sriram H. Iyer
---

## Table of Contents
  - [Overview](#overview)
  - [Pre-requisites](#pre-requisites)
  - [Network Architecture](#network-architecture)
  - [Configuring FTP in passive mode using vsftpd](#configuring-ftp-in-passive-mode-using-vsftpd)
  - [Verifying file transfer using WinSCP](#verifying-file-transfer-using-winscp)
  - [Understanding how passive FTP works with the Azure Load balancer](#understanding-how-passive-ftp-works-with-the-azure-load-balancer)
  - [Why not use Active FTP?](#why-not-use-active-ftp)

## Overview

In this blog, we will deploy Azure VMs of Ubuntu OS and configure them as FTP servers in passive mode (PASV). The Azure VMs would be in the backend pool of Azure Load Balancer (internal) for high availability.

We will use the [vsftpd](https://help.ubuntu.com/community/vsftpd) package for configuring the FTP service.

## Pre-requisites

You must have an active Azure subscription for following through the steps in this blog.

## Network Architecture

We will deploy an Azure Load Balancer with two Azure VMs and another VM as FTP client and Azure Bastion for securely accessing these VMs.

![network-diagram](https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/main/_pictures/azure-vm-passive-ftp-with-load-balancer-network-diagram.png)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fhisriram1996%2Fhisriram1996.github.io%2Frefs%2Fheads%2Fmain%2F_arm-templates%2Fazure-load-balancer-passive-ftp.json)

You could also deploy the Azure resources in the above architecture using Azure CLI commands below.

```bash
region="centralindia"
az group create --name "test-group" --location "$region"
rg=$(az group show --name "test-group" --query "name" --output "tsv")
az network nsg create --name "test-nsg" --resource-group "$rg" --location "$region"
az network public-ip create --name "nat-ip" --resource-group "$rg" --location "$region" --version "IPv4" --allocation-method Static --sku "Standard" --tier "Regional" --zone 1 2 3
az network nat gateway create --name "test-nat" --resource-group "$rg" --location "$region" --public-ip-addresses "nat-ip" --sku "Standard"
az network vnet create --name "test-vnet" --resource-group "$rg" --location "$region" --address-prefixes "10.0.0.0/24"
az network vnet subnet create --name "FTPSubnet" --vnet-name "test-vnet" --resource-group "$rg" --address-prefixes "10.0.0.0/26" --default-outbound-access "false" --nat-gateway "test-nat" --network-security-group "test-nsg"
az network vnet subnet create --name "AzureBastionSubnet" --vnet-name "test-vnet" --resource-group "$rg" --address-prefixes "10.0.0.64/26" --default-outbound-access "false"
az network public-ip create --name "bastion-ip" --resource-group "$rg" --location "$region" --version "IPv4" --allocation-method Static --sku "Standard" --tier "Regional" --zone 1 2 3
az network bastion create --name "test-bastion" --resource-group "$rg" --vnet-name "test-vnet" --public-ip-address "bastion-ip" --sku "Standard" --no-wait true
az network lb create --name "test-lb" --resource-group "$rg" --sku "Standard" --vnet-name "test-vnet" --subnet "FTPSubnet" --frontend-ip-name "ftp-ip" --backend-pool-name "ftp-pool"
az network lb probe create --name "ftp-probe" --lb-name "test-lb" --resource-group "$rg" --protocol "tcp" --port "21"
az network lb rule create --name "ftp-rule" --lb-name "test-lb" --resource-group "$rg" --frontend-ip-name "ftp-ip" --backend-pool-name "ftp-pool" --protocol "tcp" --frontend-port "21" --backend-port "21" --probe-name "ftp-probe"
for i in {1..2}; do az network nic create --name "ftp-nic-$i" --resource-group "$rg" --vnet-name "test-vnet" --subnet "FTPSubnet" --lb-name "test-lb" --lb-address-pools "ftp-pool"; done
for i in {1..2}; do az vm create --name "ftp-server-$i" --resource-group "$rg" --location "$region" --image "canonical:ubuntu-24_04-lts:server:latest" --os-disk-name "ftp-disk-$i" --nics "ftp-nic-$i" --authentication-type "password" --admin-username "<username>" --admin-password "<password>"; done
az network nic create --name "windows-nic" --resource-group "$rg" --vnet-name "test-vnet" --subnet "FTPSubnet"
az vm create --name "windows-server" --resource-group "$rg" --location "$region" --image "MicrosoftWindowsServer:WindowsServer:2025-datacenter-g2:latest" --os-disk-name "windows-disk" --nics "windows-nic" --authentication-type "password" --admin-username "<username>" --admin-password "<password>"
```

## Configuring FTP in passive mode using vsftpd

Please install the `vsftpd` package in the Ubuntu VMs in the backend pool of the Load Balancer using the command below.

```bash
sudo apt-get update && sudo apt-get install -y vsftpd
```

Please edit the configuration file `/etc/vsftpd.conf` with below content for running FTP in passive mode.

```bash
sudo vi /etc/vsftpd.conf
```

Contents of the `/etc/vsftpd.conf` file.

```bash
ftpd_banner=You are in the FTP server.
listen=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES
pasv_enable=YES
pasv_address=<VM_IP_address>
pasv_addr_resolve=YES
pasv_min_port=50000
pasv_max_port=59999
pasv_promiscuous=YES
cmds_denied=EPSV
idle_session_timeout=240
data_connection_timeout=240
```   

Please restart the `vsftpd.service` using the command below.

```bash
sudo systemctl restart vsftpd.service
```

Example:

<img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_pictures/_images_2025-10-26-Configure-passive-FTP-in-Azure-VMs-with-high-availability-using-Azure-Load-Balancer/image1.png">

## Verifying file transfer using WinSCP

We would need to install [WinSCP](https://winscp.net/eng/download.php) which is a FTP client in the VM which is not in the backend pool of the Azure Load Balancer.

Open the WinSCP and use the frontend private IP address of the Azure Load Balancer as the FTP server. The credentials would be of the VMs in the backend pool. You could then transfer the files using WinSCP.

<img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_pictures/_images_2025-10-26-Configure-passive-FTP-in-Azure-VMs-with-high-availability-using-Azure-Load-Balancer/image2.png">

## Understanding how passive FTP works with the Azure Load balancer

The Azure Load Balancer is configured with load balancing rule for TCP port 21 which is used for control connection of the FTP. The FTP client could connect to either of the VMs in the backend pool using the frontend IP address of the Azure Load Balancer. However, the backend VM sends its private IP address when entering passive mode of FTP for data connection.

The **vsftpd** service is configured with `pasv_promiscuous=YES`, so data connections are not verified to ensure they originate from the same IP address (the frontend IP address of the Azure Load Balancer). The FTP client must ensure that it does not enforce a check requiring data connections to originate from the same frontend IP address of the Azure Load Balancer to which the control connection was established; otherwise, the data connection will fail to initiate from the client.

WinSCP supports having different IP addresses for the control connection and the data connection.

<img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_pictures/_images_2025-10-26-Configure-passive-FTP-in-Azure-VMs-with-high-availability-using-Azure-Load-Balancer/image3.png">

<img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_pictures/_images_2025-10-26-Configure-passive-FTP-in-Azure-VMs-with-high-availability-using-Azure-Load-Balancer/image4.png">

We are bypassing the Azure Load Balancer for FTP data connections because a port range cannot be specified in the load balancing rule. However, setting `pasv_promiscuous=YES` in **vsftpd** disables an important security feature, which verifies that passive-mode connections originate from the same IP address as the control connection that initiates the data transfer. If it is required to set `pasv_promiscuous=NO` in `/etc/vsftpd.conf` then the load balancing rule in Azure Load Balancer must be enabled with HA ports, enabling HA ports will cause all the packets destined to the frontend IP to be forwarded to the backend VMs. You could configure NSG rule for only allowing the control and data ports of FTP. We also need to set session persistence in the load balancing rule of the Azure Load Balancer so that the data connections are forwarded to the same backend VM as the control connection. You could also consider enabling Extended Passive Mode (EPSV) in **vsftpd** by removing the line `cmds_denied=EPSV` in `/etc/vsftpd.conf` file which ensured that the IP address of the data connection is same as that of the control connection.

<img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_pictures/_images_2025-10-26-Configure-passive-FTP-in-Azure-VMs-with-high-availability-using-Azure-Load-Balancer/image5.png">

<img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_pictures/_images_2025-10-26-Configure-passive-FTP-in-Azure-VMs-with-high-availability-using-Azure-Load-Balancer/image6.png">

## Why not use Active FTP?

We can configure FTP in active mode by configuring the `/etc/vsftpd.conf` with contents below.

```bash
ftpd_banner=You are in the FTP server.
listen=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES
use_localtime=NO
connect_from_port_20=YES
idle_session_timeout=240
data_connection_timeout=240
pasv_enable=NO
cmds_denied=EPSV
```

We will configure the loopback interface with the frontend IP address of the Load Balancer in the backend VMs. The **vsftpd** service will listen to the Azure Load Balancer's frontend IP address.

```bash
sudo ip addr add <frontend_IP>/<subnet_mask> dev lo:0
```

We will then configure the Azure Load Balancer with load balancing rules for TCP port 20 and 21 with `Floating IP` enabled.

<img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_pictures/_images_2025-10-26-Configure-passive-FTP-in-Azure-VMs-with-high-availability-using-Azure-Load-Balancer/image7.png">

We need to disable passive mode in WinSCP before initiating connection to the frontend IP address of the Azure Load Balancer.

<img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_pictures/_images_2025-10-26-Configure-passive-FTP-in-Azure-VMs-with-high-availability-using-Azure-Load-Balancer/image8.png">

<img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_pictures/_images_2025-10-26-Configure-passive-FTP-in-Azure-VMs-with-high-availability-using-Azure-Load-Balancer/image9.png">

In [Active FTP](https://slacksite.com/other/ftp.html), the server initiates connection to the client's data port. We could observe that the backend VM sends the TCP **SYN** packet and the client replies with TCP **SYN+ACK**; However, the backend VM does not receive it as the Azure Load Balancer drops the packet. Hence, active FTP is not supported through the Azure Load Balancer. You would need to use Azure Firewall as it supports but active and passive FTP as documented in [Azure Firewall FTP support](https://learn.microsoft.com/en-us/azure/firewall/ftp-support).

Packet capture in the source VM (FTP client):

<img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_pictures/_images_2025-10-26-Configure-passive-FTP-in-Azure-VMs-with-high-availability-using-Azure-Load-Balancer/image10.png">

Packet capture in the destination VM (FTP server):

<img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_pictures/_images_2025-10-26-Configure-passive-FTP-in-Azure-VMs-with-high-availability-using-Azure-Load-Balancer/image11.png">

<link rel="alternate" type="application/rss+xml"  href="{{ site.url }}/feed.xml" title="{{ site.title }}">
