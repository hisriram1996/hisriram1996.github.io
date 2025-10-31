---
layout: post
title: "Deploy Azure Load Balancer using Terraform"
author: Sriram H. Iyer
---

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Deploy a Public Load Balancer](#deploy-a-public-load-balancer)
- [Deploy an Internal Load Balancer](#deploy-an-internal-load-balancer)
- [Delete the resources](#delete-the-resources)

## Overview

[Azure Load Balancer](https://learn.microsoft.com/en-us/azure/load-balancer/load-balancer-overview) is used for distributing load (incoming traffic) to multiple resources hosting the same application. This ensures high availability of the application as the Load Balancers distributes traffic to healthy resources.

There are two types of Azure Load Balancers:
1. Public Load Balancer.
2. Private or Internal Load Balancer.

Public Load Balancer has public IP address as its frontend and is used for load balancing traffic sourcing from internet. An Internal Load Balancer has private IP address as its frontend and is used for load balancing traffic to internal applications from private networks.

In this blog, we will deploy an Azure Load Balancer for distributing traffic to two Azure Virtual Machines hosting a simple Nginx web service using Terraform.

Please note that this blog assumes that you know how to deploy of Azure Load Balancers using Azure Portal and you have an Azure Subscription.

## Prerequisites

Please install [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) and [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) for deploying Azure resources.

## Deploy a Public Load Balancer

In this section, we will deploy a Public Load Balancer with Backend Pool consisting of two Azure Virtual Machines. These VMs will host a simple web page configured by using a custom script extension for Nginx web service. We will perform complete deployment using Terraform.

### Public Load Balancer Lab Setup

This is how our architecture will look after the deployment is completed.

![Network Diagram](https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/main/_pictures/azure-public-load-balancer-with-two-virtual-machines-network-diagram.png)

### Create and Deploy Terraform script

1. Create a directory and make it as your current directory.

   ```bash
   mkdir load-balancer-demo
   cd load-balancer-demo
   ```
   
2. Create a file named ```providers.tf``` and paste the configuration below. Here we have configured ```azurerm``` as Terraform provider for creating and managing our Azure resources.

   <pre id="code1"></pre>
   <script>
     fetch('https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_terraform-scripts/azure-public-load-balancer-lab/providers.tf')
       .then(response => response.text())
       .then(text => document.getElementById('code1').textContent = text);
   </script>

3. Create a file named ```variables.tf``` and paste the configuration below. We declare all the variables that we intend to use in our Terraform deployment in the ```variables.tf``` file. You could modify the default values as per your choice or naming convention for Azure resources.

   <pre id="code2"></pre>
   <script>
     fetch('https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_terraform-scripts/azure-public-load-balancer-lab/variables.tf')
       .then(response => response.text())
       .then(text => document.getElementById('code2').textContent = text);
   </script>

4. Create a file named ```main.tf``` and paste the configuration below. The ```main.tf``` is our configuration file where we use to deploy our Azure resources.

   <pre id="code3"></pre>
   <script>
     fetch('https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_terraform-scripts/azure-public-load-balancer-lab/main.tf')
       .then(response => response.text())
       .then(text => document.getElementById('code3').textContent = text);
   </script>

5. Create a file named ```outputs.tf``` and paste the configuration below. This is display the IP address in URL format which we could use for accessing our application.

   <pre id="code4"></pre>
   <script>
     fetch('https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_terraform-scripts/azure-public-load-balancer-lab/outputs.tf')
       .then(response => response.text())
       .then(text => document.getElementById('code4').textContent = text);
   </script>

6. Initialize the working directory containing Terraform configuration files (```load-balancer-demo``` in our case).

   ```bash
   terraform init -upgrade
   ```

7. Create an execution plan to preview the Terraform deployment.

   ```bash
   terraform plan -out main.tfplan
   ```

8. Apply Terraform configuration previewed in the execution plan.

   ```bash
   terraform apply main.tfplan
   ```

### Verify the deployment

When you apply the execution plan, Terraform displays the frontend public IP address. If you've cleared the screen, you can retrieve that value with the following Terraform command:

```bash
echo $(terraform output -raw public_ip_address)
```

You could verify if you could access our web page by using the frontend Public IP address of the Azure Load Balancer.

<img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_pictures/_images_2023-12-27-Deploy-Azure-Load-Balancer-using-Terraform/image2.png">

## Deploy an Internal Load Balancer

This time we will deploy an Internal Load Balancer. Since the frontend IP address of an Internal Load Balancer is private IP address, we will also deploy another Virtual Machine from where we could access the web page hosted in the backend pool VMs using the frontend IP address of an Internal Load Balancer.

### Internal Load Balancer Lab Setup

This is how our architecture will look after the deployment is completed.

![Network Diagram](https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/main/_pictures/azure-internal-load-balancer-with-two-virtual-machines-network-diagram.png)

### Create and Deploy Terraform script

1. Create a directory and make it as your current directory.

   ```bash
   mkdir internal-load-balancer-demo
   cd internal-load-balancer-demo
   ```
   
2. Create a file named ```providers.tf``` and paste the configuration below. Here we have configured ```azurerm``` as Terraform provider for creating and managing our Azure resources.

   <pre id="code5"></pre>
   <script>
     fetch('https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_terraform-scripts/azure_internal-load-balancer-lab/providers.tf')
       .then(response => response.text())
       .then(text => document.getElementById('code5').textContent = text);
   </script>

3. Create a file named ```variables.tf``` and paste the configuration below. We declare all the variables that we intend to use in our Terraform deployment in the ```variables.tf``` file. You could modify the default values as per your choice or naming convention for Azure resources.

   <pre id="code6"></pre>
   <script>
     fetch('https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_terraform-scripts/azure_internal-load-balancer-lab/variables.tf')
       .then(response => response.text())
       .then(text => document.getElementById('code6').textContent = text);
   </script>

4. Create a file named ```main.tf``` and paste the configuration below. The ```main.tf``` is our configuration file where we use to deploy our Azure resources.

   <pre id="code7"></pre>
   <script>
     fetch('https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_terraform-scripts/azure_internal-load-balancer-lab/main.tf')
       .then(response => response.text())
       .then(text => document.getElementById('code7').textContent = text);
   </script>

5. Create a file named ```outputs.tf``` and paste the configuration below. This is display the IP address in URL format which we could use for accessing our application.

   <pre id="code8"></pre>
   <script>
     fetch('https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_terraform-scripts/azure_internal-load-balancer-lab/outputs.tf')
       .then(response => response.text())
       .then(text => document.getElementById('code8').textContent = text);
   </script>

6. Initialize the working directory containing Terraform configuration files (```internal-load-balancer-demo``` in our case).

   ```bash
   terraform init -upgrade
   ```

7. Create an execution plan to preview the Terraform deployment.

   ```bash
   terraform plan -out main.tfplan
   ```

8. Apply Terraform configuration previewed in the execution plan.

   ```bash
   terraform apply main.tfplan
   ```

### Verify the deployment

Since frontend IP of an Internal Load Balancer is private IP, you cannot connect to it from internet. Connect to the VM which is not a backend pool member using SSH and verify if you could access our web page using the private IP displayed in the output ```bash apply``` command.

<img src="https://raw.githubusercontent.com/hisriram1996/hisriram1996.github.io/refs/heads/main/_pictures/_images_2023-12-27-Deploy-Azure-Load-Balancer-using-Terraform/image1.png">

## Delete the resources

In order to avoid any extra charges, it is advisable to delete the resources which are not required. You could delete all the Azure resouces which we have deployed so far using Azure Portal or by executing the following Terraform commands.

```bash
terraform plan -destroy -out main.destroy.tfplan
terraform apply main.destroy.tfplan
```

Please note that the above commands need to be executed in the working directory containing Terraform configuration files (```internal-load-balancer-demo``` in our case).

<link rel="alternate" type="application/rss+xml"  href="{{ site.url }}/feed.xml" title="{{ site.title }}">
