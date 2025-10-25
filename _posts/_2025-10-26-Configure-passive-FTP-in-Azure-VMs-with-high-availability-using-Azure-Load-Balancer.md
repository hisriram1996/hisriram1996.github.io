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
- [Understanding how passive FTP works with the Azure Load balancer](#understanding-how-passive-FTP-works-with-the-azure-load-balancer)

## Overview

In this blog, we will deploy Azure VMs of Ubuntu OS and configure them as FTP servers in passive mode. The Azure VMs would be in the backend pool of Azure Load Balancer (internal) for high availability.

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
pasv_address=10.0.0.5
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

## Verifying file transfer using WinSCP



## Understanding how passive FTP works with the Azure Load balancer

Example:

<img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_pictures/_images_2024-11-05-Configure-cloudinit-in-Azure-VM/image1.png">

We could debug any issues in `cloud-init` configuration of Azure VM by following this [public guidance](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/cloud-init-troubleshooting) from Azure.

<link rel="alternate" type="application/rss+xml"  href="{{ site.url }}/feed.xml" title="{{ site.title }}">
