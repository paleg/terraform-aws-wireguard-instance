module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name            = var.name
  use_name_prefix = false
  description     = "Security group for WireGuard instance ${var.name}"

  vpc_id = var.vpc_id != null ? var.vpc_id : data.aws_vpc.default.id

  ingress_with_cidr_blocks = [
    {
      from_port   = var.wireguard_port
      to_port     = var.wireguard_port
      protocol    = "udp"
      cidr_blocks = "0.0.0.0/0"
      description = "Anywhere"
    },
    {
      rule        = "ssh-tcp"
      cidr_blocks = join(",", var.admin_locations)
      description = "Admin IP"
    },
  ]

  egress_rules            = ["all-all"]
  egress_ipv6_cidr_blocks = []
}

moved {
  from = aws_security_group.this
  to   = module.security_group.aws_security_group.this[0]
}

moved {
  from = aws_security_group_rule.egress
  to   = module.security_group.aws_security_group_rule.egress_rules[0]
}

moved {
  from = aws_security_group_rule.ingress_wireguard
  to   = module.security_group.aws_security_group_rule.ingress_with_cidr_blocks[0]
}

moved {
  from = aws_security_group_rule.ingress_ssh
  to   = module.security_group.aws_security_group_rule.ingress_with_cidr_blocks[1]
}
