#!/bin/bash
read -p "Enter the username of the VM: " username
read -s -p "Enter the password of the VM: " password
echo
read -p "Enter the resource group: " grp
read -p "Enter the region: " region
read -s -p "Enter the pre-shared key for the VPN: " psk
echo
echo "Deployment started"
az group create --name $grp --location $region
az network public-ip create --name "vpn-ip" --resource-group $grp --location $region --allocation-method "Static" --sku "Standard" --zone 1 2 3
az network public-ip create --name "router-ip" --resource-group $grp --location $region --allocation-method "Static" --sku "Standard" --zone 1 2 3
vpnip=$(az network public-ip show --name "vpn-ip" --resource-group $grp --query "ipAddress" --output tsv)
routerip=$(az network public-ip show --name "router-ip" --resource-group $grp --query "ipAddress" --output tsv)
az network asg create --name "test-asg" --resource-group $grp --location $region
az network nsg create --name "test-nsg" --resource-group $grp --location $region
az network vnet create --name "test-vnet" --resource-group $grp --location $region --address-prefix "192.168.0.0/24"
az network vnet subnet create --name "GatewaySubnet" --vnet-name "test-vnet" --resource-group $grp --address-prefixes "192.168.0.0/27"
az network vnet create --name "datacenter-network" --resource-group $grp --location $region --address-prefix "172.16.0.0/24"
az network vnet subnet create --name "router-subnet" --vnet-name "datacenter-network" --resource-group $grp --address-prefixes "172.16.0.0/29" --network-security-group "test-nsg"
az network nic create --name "router-nic" --resource-group $grp --location $region --subnet "router-subnet" --vnet-name "datacenter-network" --private-ip-address "172.16.0.4" --ip-forwarding "true" --public-ip-address "router-ip" --application-security-groups "test-asg"
az network nsg rule create --name "AllowVPNOut" --nsg-name "test-nsg" --resource-group $grp --protocol "Udp" --direction "Outbound" --access "Allow" --priority "3000" --source-asgs "test-asg" --source-port-ranges 500 4500 --destination-address-prefixes $vpnip --destination-port-ranges 500 4500
az network nsg rule create --name "AllowESPOut" --nsg-name "test-nsg" --resource-group $grp --protocol "Esp" --direction "Outbound" --access "Allow" --priority "4000" --source-asgs "test-asg" --source-port-ranges "*" --destination-address-prefixes $vpnip --destination-port-ranges "*"
az network nsg rule create --name "AllowSSHIn" --nsg-name "test-nsg" --resource-group $grp --protocol "Tcp" --direction "Inbound" --access "Allow" --priority "2000" --source-address-prefixes "Internet" --source-port-ranges "*" --destination-asgs "test-asg" --destination-port-ranges 22000
az network nsg rule create --name "AllowVPNIn" --nsg-name "test-nsg" --resource-group $grp --protocol "Udp" --direction "Inbound" --access "Allow" --priority "3000" --source-address-prefixes $vpnip --source-port-ranges 500 4500 --destination-asgs "test-asg" --destination-port-ranges 500 4500
az network nsg rule create --name "AllowESPIn" --nsg-name "test-nsg" --resource-group $grp --protocol "Esp" --direction "Inbound" --access "Allow" --priority "4000" --source-address-prefixes $vpnip --source-port-ranges "*" --destination-asgs "test-asg" --destination-port-ranges "*"
az network vnet-gateway create --name "test-vpngw" --resource-group $grp --vnet "test-vnet" --gateway-type "Vpn" --sku "VpnGw1AZ" --public-ip-address "vpn-ip" --asn "65515"
az network vnet-gateway update --name "test-vpngw" --resource-group $grp --set "bgpSettings.bgpPeeringAddresses[0].customBgpIpAddresses=['169.254.21.2']"
az network local-gateway create --name "test-lgw" --resource-group $grp --gateway-ip-address $routerip --asn 65100 --bgp-peering-address "169.254.21.1"
az network vpn-connection create --name "test-connection" --resource-group $grp --vnet-gateway1 "test-vpngw" --local-gateway2 "test-lgw" --authentication-type "PSK" --shared-key $psk --enable-bgp
cat > cloud-config.txt << EOF
#cloud-config
package_reboot_if_required: true
package_update: true
package_upgrade: true
packages:
  - apt-transport-https
  - ca-certificates
  - coreutils
  - bird3
  - bind9-utils
  - curl
  - dnsutils
  - gnupg
  - lsb-release
  - mtr
  - nmap
  - net-tools
  - openssl
  - sslscan
  - strongswan
  - strongswan-pki
  - libstrongswan-extra-plugins
  - tcpdump
  - traceroute
  - tcptraceroute
  - whois
  - wget
  - zip
  - unzip
write_files:
  - path: /etc/sysctl.d/99-ip-forward.conf
    content: |
      # Enable IPv4 packet forwarding
      net.ipv4.ip_forward = 1
    permissions: '0755'
  - path: /etc/swanctl/swanctl.conf
    content: |
      connections {
          azure_vpn {
              version = 2
              local_addrs = 172.16.0.4
              remote_addrs = $vpnip
              proposals = aes256-sha256-modp1024
              local {
                  auth = psk
                  id = 172.16.0.4
              }
              remote {
                  auth = psk
                  id = $vpnip
              }
              children {
                  azure_vpn_childsa {
                      mark_in = 42
                      mark_out = 42
                      local_ts = 0.0.0.0/0
                      remote_ts = 0.0.0.0/0
                      esp_proposals = aes256-sha256
                      dpd_action = restart
                      start_action = start
                      updown = /usr/local/sbin/vti-updown.sh
                  }
              }
              reauth_time = 28800s
              keyingtries = 0
              dpd_delay = 45s
          }
      }
      secrets {
          ike {
              id-1 = 172.16.0.4
              id-2 = $vpnip
              secret = "$psk"
          }
      }
    permissions: '0755'
  - path: /usr/local/sbin/vti-updown.sh
    content: |
      #!/bin/bash
      if [ "\$PLUTO_VERB" = "up-client" ]; then
        ip route replace 169.254.21.0/30 dev vti0 table 220
        ip route replace 169.254.21.0/30 dev vti0 table main
      fi
      if [ "\$PLUTO_VERB" = "down-client" ]; then
        ip route del 169.254.21.0/30 dev vti0 table 220 2>/dev/null
        ip route del 169.254.21.0/30 dev vti0 table main 2>/dev/null
      fi
    permissions: '0755'
  - path: /etc/bird/bird.conf
    content: |
      router id 172.16.0.4;
      protocol kernel {
            scan time 60;
            ipv4 {
                  import none;
                  export all;
            };
      }
      protocol device {
            scan time 60;
      }
      protocol direct {
            ipv4;
            interface "eth0";
      }
      protocol static {
            ipv4;
            route 169.254.21.2/32 via "vti0";
      }
      protocol bgp azure_vpn {
            router id 169.254.21.1;
            local 169.254.21.1 as 65100;
            neighbor 169.254.21.2 as 65515;
            multihop;
            keepalive time 60;
            hold time 180;
            ipv4 {
                  import all;
                  export all;
                  next hop self;
            };
            enable route refresh on;
      }
    permissions: '0755'
runcmd:
  - sudo sysctl --system
  - sudo sed -i 's/#Port 22/Port 22000/g' /etc/ssh/sshd_config
  - sudo ip tunnel add vti0 local 172.16.0.4 remote $vpnip mode vti key 42
  - sudo sysctl -w net.ipv4.conf.vti0.disable_policy=1
  - sudo sysctl -w net.ipv4.conf.vti0.rp_filter=0
  - sudo ip addr add 169.254.21.1/30 dev vti0
  - sudo ip link set vti0 up
  - sudo swanctl --load-all
  - sudo swanctl --initiate --child azure_vpn_childsa
  - sudo systemctl daemon-reload
  - sudo systemctl restart ssh
  - sudo systemctl restart bird
EOF
az vm create --name "datacenter-router" --resource-group $grp --location $region --image "canonical:ubuntu-26_04-lts:server:latest" --size "Standard_D2as_v4" --os-disk-name "router-disk" --nics "router-nic" --authentication-type "password" --admin-username $username --admin-password $password --custom-data cloud-config.txt
rm -rf cloud-config.txt
echo "Deployment completed"