output "private_ip_address" {
  value = "http://${azurerm_lb.my_lb.private_ip_address}"
}
