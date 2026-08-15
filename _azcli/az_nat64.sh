#!/bin/bash
read -p "Enter the resource group: " rg
read -p "Enter the region: " region
read -p "Enter the username of the VM: " username
read -s -p "Enter the password of the VM: " password
echo
echo "Deployment started"
az group create --name $rg --location $region
az network public-ip create --name "test-ip" --resource-group $rg --allocation-method "Static" --sku "StandardV2" --tier "Regional" --version "IPv4" --zone 1 2 3
az network nat gateway create --name "test-nat" --resource-group $rg --location $region --public-ip-addresses "test-ip" --sku "StandardV2" --zone 1 2 3 --nat64 "Enabled"
natgw=$(az network nat gateway show --name "test-nat" --resource-group $rg --query "id" --output tsv)
az monitor log-analytics workspace create --name "test-log" --resource-group $rg --sku "Standalone"
az monitor diagnostic-settings create --name "test-diag" --resource $natgw --export-to-resource-specific "true" --workspace "test-log" --logs "[{categoryGroup:allLogs,enabled:true,retention-policy:{enabled:false,days:0}}]" --metrics "[{category:AllMetrics,enabled:false,retention-policy:{enabled:false,days:0}}]"
az network nsg create --name "test-nsg" --resource-group $rg --location $region
az network vnet create --name "test-vnet" --resource-group $rg --location $region --address-prefixes "192.168.1.0/24" "fd12:3456:789a:0100::/64"
az network vnet subnet create --name "AzureVMSubnet" --vnet-name "test-vnet" --resource-group $rg --address-prefixes "192.168.1.0/26" "fd12:3456:789a:0100::/64" --network-security-group "test-nsg" --nat-gateway $natgw
az network vnet subnet create --name "AzureBastionSubnet" --vnet-name "test-vnet" --resource-group $rg --address-prefixes "192.168.1.64/26"
az network public-ip create --name "bastion-ip" --resource-group $rg --allocation-method "Static" --sku "Standard" --zone 1 2 3
az network bastion create --name "test-bastion" --resource-group $rg --vnet-name "test-vnet" --disable-copy-paste "false" --enable-ip-connect "true" --enable-tunneling "true" --file-copy "true" --public-ip-address "bastion-ip" --scale-units 2 --sku "Standard"
az network nic create --name "server-nic" --resource-group $rg --location $region --subnet "AzureVMSubnet" --vnet-name "test-vnet" --private-ip-address "192.168.1.4"
az network nic ip-config create --name "ipv6cconfig" --nic-name "server-nic" --resource-group $rg --subnet "AzureVMSubnet" --vnet-name "test-vnet" --private-ip-address-version "IPv6" --private-ip-address "fd12:3456:789a:0100::4"
az network nic create --name "client-nic" --resource-group $rg --location $region --subnet "AzureVMSubnet" --vnet-name "test-vnet" --private-ip-address "192.168.1.5"
az network nic ip-config create --name "ipv6cconfig" --nic-name "client-nic" --resource-group $rg --subnet "AzureVMSubnet" --vnet-name "test-vnet" --private-ip-address-version "IPv6" --private-ip-address "fd12:3456:789a:0100::5"
cat > cloud-config.txt << EOF
#cloud-config
package_reboot_if_required: true
package_update: true
package_upgrade: true
packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - coreutils
  - bind9
  - bind9-utils
  - dnsutils
  - gnupg
  - lsb-release
  - mtr
  - nmap
  - net-tools
  - openssl
  - sslscan
  - tcpdump
  - traceroute
  - tcptraceroute
  - whois
  - wget
  - zip
  - unzip
write_files:
  - path: /etc/bind/named.conf.options
    content: |
      options {
              directory "/var/cache/bind";
              allow-query { any; };
              allow-query-cache { any; };
              allow-recursion { any; };
              forwarders {
                      168.63.129.16;
              };
              dnssec-validation no;
              listen-on { any; };
              listen-on-v6 { any; };
              dns64 64:ff9b::/96 {
                      recursive-only yes;
                      suffix ::;
              };
      };
    permissions: '0755'
runcmd:
  - sudo systemctl daemon-reload
  - sudo systemctl restart bind9
EOF
az vm create --name "dns-server" --resource-group $rg --location $region --image "canonical:ubuntu-26_04-lts:server:latest" --size "Standard_D2as_v4" --os-disk-name "server-disk" --nics "server-nic" --authentication-type "password" --admin-username $username --admin-password $password --custom-data "cloud-config.txt"
rm "cloud-config.txt"
az network vnet update --name "test-vnet" --resource-group $rg --dns-servers "192.168.1.4" "fd12:3456:789a:0100::4"
az vm create --name "dns-client" --resource-group $rg --location $region --image "canonical:ubuntu-26_04-lts:server:latest" --size "Standard_D2as_v4" --os-disk-name "client-disk" --nics "client-nic" --authentication-type "password" --admin-username $username --admin-password $password
echo "Deployment completed"
