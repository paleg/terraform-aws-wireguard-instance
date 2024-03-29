output "security_group_id" {
  value = module.security_group.security_group_id
}

output "eip_public_address" {
  value = aws_eip.this.public_ip
}

output "wireguard_port" {
  value = var.wireguard_port
}

output "iam_role_arn" {
  value = module.iam_role.iam_role_arn
}

output "iam_role_name" {
  value = module.iam_role.iam_role_name
}