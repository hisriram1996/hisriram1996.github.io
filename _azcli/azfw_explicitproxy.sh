#!/bin/bash
read -p "Enter the resource group: " rg
read -p "Enter the region: " region
read -p "Enter the username of the VM: " username
read -s -p "Enter the password of the VM: " password
echo
echo "Deployment started"
az group create --name $rg --location $region
az network asg create --name "test-asg" --resource-group $rg --location $region
az network nsg create --name "test-nsg" --resource-group $rg --location $region
az network vnet create --name "test-vnet" --resource-group $rg --location $region --address-prefix "192.168.1.0/24"
az network route-table create --name "test-udr" --resource-group $rg
az network route-table route create --name "default-route" --route-table-name "test-udr" --resource-group $rg --address-prefix "0.0.0.0/0" --next-hop-type "VirtualAppliance" --next-hop-ip-address "192.168.1.132"
az network vnet subnet create --name "AzVMSubnet" --vnet-name "test-vnet" --resource-group $rg --address-prefixes "192.168.1.0/26" --network-security-group "test-nsg" --route-table "test-udr"
az network vnet subnet create --name "AzWebSubnet" --vnet-name "test-vnet" --resource-group $rg --address-prefixes "192.168.1.64/26" --network-security-group "test-nsg"
az network vnet subnet create --name "AzureFirewallSubnet" --vnet-name "test-vnet" --resource-group $rg --address-prefixes "192.168.1.128/26"
az network vnet subnet create --name "AzureFirewallManagementSubnet" --vnet-name "test-vnet" --resource-group $rg --address-prefixes "192.168.1.192/26"
az network public-ip create --name "test-fwip" --resource-group $rg --location $region --allocation-method "Static" --sku "Standard" --zone 1 2 3
az network public-ip create --name "test-mgmtip" --resource-group $rg --location $region --allocation-method "Static" --sku "Standard" --zone 1 2 3
az monitor log-analytics workspace create --name "test-log" --resource-group $rg --sku "Standalone"
fwip=$(az network public-ip show --name "test-fwip" --resource-group $rg --query "[name]" --output tsv)
fwipaddr=$(az network public-ip show --name "test-fwip" --resource-group $rg --query "[ipAddress]" --output tsv)
mgmtip=$(az network public-ip show --name "test-mgmtip" --resource-group $rg --query "[name]" --output tsv)
az network firewall policy create --name "test-policy" --resource-group $rg --sku "Standard" --explicit-proxy enable-explicit-proxy=true http-port=9001
az network firewall policy rule-collection-group create --name "rule-group" --policy-name "test-policy" --resource-group $rg --priority 1000
az network firewall policy rule-collection-group collection add-filter-collection --name "app-rule-collection" --rule-collection-group-name "rule-group" --policy-name "test-policy" --resource-group $rg --collection-priority 1000 --action "Allow" --rule-name "allow_www-example-com" --rule-type "ApplicationRule" --source-addresses "192.168.1.0/24" --target-fqdns "www.example.com" --protocols Http=8080
az network firewall policy rule-collection-group collection add-nat-collection --name "dnat-rule-collection" --rule-collection-group-name "rule-group" --policy-name "test-policy" --resource-group $rg --collection-priority 2000 --action "DNAT" --rule-name "allow-ssh" --ip-protocols "TCP" --source-addresses "0.0.0.0/0" --destination-addresses $fwipaddr --destination-ports 22 --translated-address "192.168.1.4" --translated-port "22"
az network firewall create --name "test-azfw" --resource-group $rg --firewall-policy "test-policy" --m-conf-name "mgmt-ipconfig" --m-public-ip $mgmtip --conf-name "ipconfig" --public-ip $fwip --sku "AZFW_VNet" --tier "Standard" --vnet-name "test-vnet" --zones 1 2 3
azfw=$(az network firewall show --name "test-azfw" --resource-group $rg --query "[id]" --output tsv)
az monitor diagnostic-settings create --name "test-diag" --resource $azfw --export-to-resource-specific "true" --workspace "test-log" --logs "[{categoryGroup:allLogs,enabled:true,retention-policy:{enabled:false,days:0}}]" --metrics "[{category:AllMetrics,enabled:false,retention-policy:{enabled:false,days:0}}]"
az network nic create --name "test-nic" --resource-group $rg --location $region --subnet "AzVMSubnet" --vnet-name "test-vnet" --private-ip-address "192.168.1.4"
az vm create --name "test-vm" --resource-group $rg --location $region --image "canonical:ubuntu-26_04-lts:server:latest" --size "Standard_B2s" --os-disk-name "test-disk" --nics "test-nic" --authentication-type "password" --admin-username $username --admin-password $password
az network public-ip create --name "test-webip" --resource-group $rg --location $region --allocation-method "Static" --sku "Standard" --zone 1 2 3
webip=$(az network public-ip show --name "test-webip" --resource-group $rg --query "[name]" --output tsv)
az network nic create --name "test-webnic" --resource-group $rg --location $region --subnet "AzWebSubnet" --vnet-name "test-vnet" --private-ip-address "192.168.1.68" --public-ip-address $webip  --application-security-groups "test-asg"
az network nsg rule create --name "AllowSSHIn" --nsg-name "test-nsg" --resource-group $rg --protocol "Tcp" --direction "Inbound" --access "Allow" --priority "100" --source-address-prefixes "Internet" --source-port-ranges "*" --destination-asgs "test-asg" --destination-port-ranges 22000
az network nsg rule create --name "AllowHTTPIn" --nsg-name "test-nsg" --resource-group $rg --protocol "Tcp" --direction "Inbound" --access "Allow" --priority "200" --source-address-prefixes "Internet" --source-port-ranges "*" --destination-asgs "test-asg" --destination-port-ranges 8080
cat > cloud-config.txt << EOF
#cloud-config
package_reboot_if_required: true
package_update: true
package_upgrade: true
packages:
  - apt-transport-https
  - ca-certificates
  - bind9-utils
  - curl
  - gnupg
  - lsb-release
  - nginx
write_files:
  - path: /var/www/www.example.com/index.html
    content: |
      <h1>Hello World!<h1>
  - path: /etc/nginx/sites-enabled/www.example.com
    content: |
      server {
        listen 8080;
        listen [::]:8080;
        server_name www.example.com;
        access_log /var/log/nginx/nginx.vhost.access.log;
        error_log /var/log/nginx/nginx.vhost.error.log;
        root /var/www/www.example.com;
        index index.html;
        location / {
          try_files $uri $uri/ =404;
        }
      }
    permissions: '0755'
runcmd:
  - sudo sed -i 's/#Port 22/Port 22000/g' /etc/ssh/sshd_config
  - sudo systemctl daemon-reload
  - sudo systemctl restart ssh
  - sudo systemctl restart nginx
EOF
az vm create --name "test-webvm" --resource-group $rg --location $region --image "canonical:ubuntu-26_04-lts:server:latest" --size "Standard_B2s" --os-disk-name "test-webdisk" --nics "test-webnic" --authentication-type "password" --admin-username $username --admin-password $password --custom-data "cloud-config.txt"
rm -f "cloud-config.txt"
az network private-dns zone create --name "example.com" --resource-group $rg
az network private-dns record-set a create --name "www" --zone-name "example.com" --resource-group $rg --ttl 10
webip=$(az network public-ip show --name "test-webip" --resource-group $rg --query "[ipAddress]" --output tsv)
az network private-dns record-set a add-record --ipv4-address $webip --record-set-name "www" --resource-group $rg --zone-name "example.com"
az network private-dns link vnet create --name "example-link" --zone-name "example.com" --virtual-network "test-vnet" --resource-group $rg --registration-enabled "false"
echo "Deployment completed"
