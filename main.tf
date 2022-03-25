data "aws_region" "current" {}

data "aws_default_tags" "this" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "this" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "defaultForAz"
    values = [true]
  }
}

resource "aws_security_group" "this" {
  name        = var.name
  vpc_id      = var.vpc_id != null ? var.vpc_id : data.aws_vpc.default.id
  description = "Security group for WireGuard instance ${var.name}"

  tags = {
    Name = var.name
  }
}

resource "aws_security_group_rule" "egress" {
  security_group_id = aws_security_group.this.id
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  to_port           = 65535
  protocol          = "all"
}

resource "aws_security_group_rule" "ingress_wireguard" {
  security_group_id = aws_security_group.this.id
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = var.wireguard_port
  to_port           = var.wireguard_port
  protocol          = "udp"
}

resource "aws_security_group_rule" "ingress_ssh" {
  security_group_id = aws_security_group.this.id
  type              = "ingress"
  cidr_blocks       = var.admin_locations
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
}

resource "aws_network_interface" "this" {
  security_groups = [aws_security_group.this.id]
  subnet_id       = var.subnet_id != null ? var.subnet_id : data.aws_subnets.this.ids[0]
  description     = "ENI for ${var.name} WireGuard instance"

  tags = {
    Name = "${var.name} EIP"
  }
}

resource "aws_eip" "this" {
  network_interface = aws_network_interface.this.id

  tags = {
    Name = var.name
  }
}

data "aws_ami" "this" {
  owners      = [var.ami_owner]
  most_recent = true

  filter {
    name   = "name"
    values = [var.ami_filter]
  }
}

resource "aws_key_pair" "vpn" {
  count = var.pub_key != null ? 1 : 0

  key_name   = var.name
  public_key = var.pub_key
}

resource "aws_launch_template" "this" {
  name     = var.name
  image_id = data.aws_ami.this.id
  key_name = var.pub_key != null ? aws_key_pair.vpn[0].id : null

  update_default_version = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.this.arn
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.this.id]
    delete_on_termination       = true
  }

  user_data = base64encode(join("\n", [
    "#cloud-config",
    yamlencode({
      write_files : [
        {
          path : "/tmp/configure.sh",
          content : templatefile(
            "${path.module}/templates/configure.sh",
            {
              eni_id     = aws_network_interface.this.id,
              eni_if     = "ens6",
              aws_region = data.aws_region.current.name,
            }
          ),
          permissions : "0755",
        },
        {
          path : "/etc/network/interfaces.d/wg0",
          content : templatefile(
            "${path.module}/templates/wg0",
            {
              eni_if = "ens6",
            }
          ),
          permissions : "0755",
        },
        {
          path : "/etc/wireguard/server.conf",
          content : templatefile(
            "${path.module}/templates/server.conf",
            {
              server_private_key = var.wireguard_private_key,
              server_port        = var.wireguard_port,
              peers              = var.wireguard_peers,
            }
          ),
          permissions : "0755",
        },
      ],
      runcmd : ["/tmp/configure.sh"]
    })
  ]))

  description = "Launch template for WireGuard instance ${var.name}"
}

resource "aws_autoscaling_group" "this" {
  name                = var.name
  desired_capacity    = var.enabled ? 1 : 0
  min_size            = var.enabled ? 1 : 0
  max_size            = 1
  vpc_zone_identifier = var.subnet_id != null ? [var.subnet_id] : [data.aws_subnets.this.ids[0]]

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = var.use_spot_instance ? 0 : 1
      on_demand_percentage_above_base_capacity = var.use_spot_instance ? 0 : 100
    }
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.this.id
        version            = aws_launch_template.this.latest_version
      }
      dynamic "override" {
        for_each = var.instance_types
        content {
          instance_type = override.value
        }
      }
    }
  }

  instance_refresh {
    strategy = "Rolling"
    triggers = ["tag"]
    preferences {
      instance_warmup        = 120
      min_healthy_percentage = 100
    }
  }

  tag {
    key                 = "Name"
    value               = var.name
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = data.aws_default_tags.this.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

resource "aws_iam_instance_profile" "this" {
  name = var.name
  role = aws_iam_role.this.name
}

resource "aws_iam_role" "this" {
  name               = var.name
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ssm" {
  policy_arn = var.ssm_policy_arn
  role       = aws_iam_role.this.name
}

resource "aws_iam_role_policy" "eni" {
  role   = aws_iam_role.this.name
  name   = var.name
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AttachNetworkInterface"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}