output "security_group_id" {
  value = aws_security_group.this.id
}

output "eip_public_address" {
  value = aws_eip.this.public_ip
}

output "wireguard_port" {
  value = var.wireguard_port
}
