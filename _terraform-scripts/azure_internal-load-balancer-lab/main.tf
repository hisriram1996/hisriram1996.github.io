#Create Resource Group
resource "azurerm_resource_group" "my_resource_group" {
  location = var.resource_group_location
  name = var.resource_group_name
}

# Create Virtual Network
resource "azurerm_virtual_network" "my_virtual_network" {
  name = var.virtual_network_name
  address_space = ["10.0.0.0/16"]
  location = azurerm_resource_group.my_resource_group.location
  resource_group_name = azurerm_resource_group.my_resource_group.name
}

# Create a subnet in the Virtual Network
resource "azurerm_subnet" "my_subnet" {
  name = var.subnet_name
  resource_group_name = azurerm_resource_group.my_resource_group.name
  virtual_network_name = azurerm_virtual_network.my_virtual_network.name
  address_prefixes = ["10.0.1.0/24"]
}

# Create Network Security Group and rules
resource "azurerm_network_security_group" "my_nsg" {
  name = var.network_security_group_name
  location = azurerm_resource_group.my_resource_group.location
  resource_group_name = azurerm_resource_group.my_resource_group.name

  security_rule {
    name = "ssh"
    priority = 1022
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = "22"
    source_address_prefix = "*"
    destination_address_prefix = "10.0.1.0/24"
  }

  security_rule {
    name = "web"
    priority = 1080
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = "80"
    source_address_prefix = "*"
    destination_address_prefix = "10.0.1.0/24"
  }
}

# Associate the Network Security Group to the subnet
resource "azurerm_subnet_network_security_group_association" "my_nsg_association" {
  subnet_id = azurerm_subnet.my_subnet.id
  network_security_group_id = azurerm_network_security_group.my_nsg.id
}

# Create Public IPs
resource "azurerm_public_ip" "my_public_ip" {
  count = 2
  name = "${var.public_ip_name}-${count.index}"
  location = azurerm_resource_group.my_resource_group.location
  resource_group_name = azurerm_resource_group.my_resource_group.name
  allocation_method = "Static"
  sku = "Standard"
}

# Create a NAT Gateway for outbound internet access of the Virtual Machines in the Backend Pool of the Load Balancer
resource "azurerm_nat_gateway" "my_nat_gateway" {
  name = var.nat_gateway
  location = azurerm_resource_group.my_resource_group.location
  resource_group_name = azurerm_resource_group.my_resource_group.name
  sku_name = "Standard"
}

# Associate one of the Public IPs to the NAT Gateway
resource "azurerm_nat_gateway_public_ip_association" "my_nat_gateway_ip_association" {
  nat_gateway_id = azurerm_nat_gateway.my_nat_gateway.id
  public_ip_address_id = azurerm_public_ip.my_public_ip[0].id
}

# Associate the NAT Gateway to subnet
resource "azurerm_subnet_nat_gateway_association" "my_nat_gateway_subnet_association" {
  subnet_id = azurerm_subnet.my_subnet.id
  nat_gateway_id = azurerm_nat_gateway.my_nat_gateway.id
}

# Create Network Interfaces
resource "azurerm_network_interface" "my_nic" {
  count = 3
  name = "${var.network_interface_name}-${count.index}"
  location = azurerm_resource_group.my_resource_group.location
  resource_group_name = azurerm_resource_group.my_resource_group.name

  ip_configuration {
    name = "ipconfig-${count.index}"
    subnet_id = azurerm_subnet.my_subnet.id
    private_ip_address_allocation = "Dynamic"
    primary = true
  }
}

# Associate one of the Public IPs to the Network Interface which is not associated to Backend Pool of the Load Balancer 
resource "azurerm_network_interface" "my_nic2" {
  name = "${var.network_interface_name}-2"
  location = azurerm_resource_group.my_resource_group.location
  resource_group_name = azurerm_resource_group.my_resource_group.name

  ip_configuration {
    name = "ipconfig-2"
    subnet_id = azurerm_subnet.my_subnet.id
    private_ip_address_allocation = "Dynamic"
    primary = true
    public_ip_address_id = azurerm_public_ip.my_public_ip[1].id
  }
}

# Associate Network Interface to the Backend Pool of the Load Balancer
resource "azurerm_network_interface_backend_address_pool_association" "my_nic_lb_pool" {
  count = 2
  network_interface_id = azurerm_network_interface.my_nic[count.index].id
  ip_configuration_name = "ipconfig-${count.index}"
  backend_address_pool_id = azurerm_lb_backend_address_pool.my_lb_pool.id
}

# Create Virtual Machine
resource "azurerm_linux_virtual_machine" "my_vm" {
  count = 3
  name = "${var.virtual_machine_name}-${count.index}"
  location = azurerm_resource_group.my_resource_group.location
  resource_group_name = azurerm_resource_group.my_resource_group.name
  network_interface_ids = [azurerm_network_interface.my_nic[count.index].id]
  size = var.virtual_machine_size

  os_disk {
    name = "${var.disk_name}-${count.index}"
    caching = "ReadWrite"
    storage_account_type = var.redundancy_type
  }

  source_image_reference {
    publisher = "Canonical"
    offer = "0001-com-ubuntu-server-jammy"
    sku = "22_04-lts-gen2"
    version = "latest"
  }

  admin_username = var.username
  admin_password = var.password
  disable_password_authentication = false

}

# Enable virtual machine extension and install Nginx
resource "azurerm_virtual_machine_extension" "my_vm_extension" {
  count = 2
  name = "Nginx"
  virtual_machine_id = azurerm_linux_virtual_machine.my_vm[count.index].id
  publisher = "Microsoft.Azure.Extensions"
  type = "CustomScript"
  type_handler_version = "2.0"

  settings = <<SETTINGS
 {
  "commandToExecute": "sudo apt-get update && sudo apt-get install nginx -y && echo \"Hello World from $(hostname)\" > /var/www/html/index.html && sudo systemctl restart nginx"
 }
SETTINGS

}

# Create an Internal Load Balancer
resource "azurerm_lb" "my_lb" {
  name = var.load_balancer_name
  location = azurerm_resource_group.my_resource_group.location
  resource_group_name = azurerm_resource_group.my_resource_group.name
  sku = "Standard"

  frontend_ip_configuration {
    name = "frontend-ip"
    subnet_id = azurerm_subnet.my_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_lb_backend_address_pool" "my_lb_pool" {
  loadbalancer_id = azurerm_lb.my_lb.id
  name = "test-pool"
}

resource "azurerm_lb_probe" "my_lb_probe" {
  resource_group_name = azurerm_resource_group.my_resource_group.name
  loadbalancer_id = azurerm_lb.my_lb.id
  name = "test-probe"
  port = 80
}

resource "azurerm_lb_rule" "my_lb_rule" {
  resource_group_name = azurerm_resource_group.my_resource_group.name
  loadbalancer_id = azurerm_lb.my_lb.id
  name = "test-rule"
  protocol = "Tcp"
  frontend_port = 80
  backend_port = 80
  disable_outbound_snat = true
  frontend_ip_configuration_name = "frontend-ip"
  probe_id = azurerm_lb_probe.my_lb_probe.id
  backend_address_pool_ids = [azurerm_lb_backend_address_pool.my_lb_pool.id]
}
