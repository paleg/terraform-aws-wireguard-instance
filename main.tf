data "aws_caller_identity" "current" {}
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

resource "aws_network_interface" "this" {
  security_groups = [module.security_group.security_group_id]
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

data "aws_ami" "_" {
  for_each = var.instances

  owners      = [var.ami_owner]
  most_recent = true

  filter {
    name   = "name"
    values = [each.value.ami_filter]
  }
}

resource "aws_key_pair" "vpn" {
  count = var.pub_key != null ? 1 : 0

  key_name   = var.name
  public_key = var.pub_key
}

resource "aws_launch_template" "_" {
  for_each = var.instances

  name        = "${var.name}-${each.key}"
  description = "Launch template for WireGuard instance ${var.name} (${each.key})"

  image_id = data.aws_ami._[each.key].id
  key_name = var.pub_key != null ? aws_key_pair.vpn[0].id : null

  update_default_version = true

  iam_instance_profile {
    arn = module.iam_role.iam_instance_profile_arn
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [module.security_group.security_group_id]
    delete_on_termination       = true
  }

  user_data = data.cloudinit_config.this.rendered
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
        launch_template_id = aws_launch_template._[keys(var.instances)[0]].id
        version            = aws_launch_template._[keys(var.instances)[0]].latest_version
      }
      dynamic "override" {
        for_each = merge(flatten([for arch, props in var.instances : [
          for instance_type in props.instance_types : {
            (instance_type) : arch
          }
          ]
        ])...)
        content {
          instance_type = override.key

          launch_template_specification {
            launch_template_id = aws_launch_template._[override.value].id
          }
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

module "secretsmanager_secret_server_conf" {
  source  = "terraform-aws-modules/secrets-manager/aws"
  version = "~> 1.1"

  name          = local.server_conf_secret_name
  secret_string = local.server_conf

  create_policy       = true
  block_public_policy = true
  policy_statements = {
    read = {
      sid = "AllowEc2Read"
      principals = [{
        type        = "AWS"
        identifiers = [module.iam_role.iam_role_arn]
      }]
      actions   = ["secretsmanager:GetSecretValue"]
      resources = ["*"]
    }
  }
}

resource "aws_ssm_document" "update_peers" {
  name          = "${var.name}-update-peers"
  document_type = "Command"

  target_type = "/AWS::EC2::Instance"

  content = templatefile(
    "${path.module}/templates/update-peers.tftpl.json",
    {
      server_conf_secret_name : module.secretsmanager_secret_server_conf.secret_id
      server_conf_path : local.server_conf_path
      aws_region : data.aws_region.current.name
    }
  )
}

resource "terraform_data" "server_conf" {
  input = md5(local.server_conf)
}

resource "aws_ssm_association" "update_peers" {
  association_name = "${var.name}-update-peers"
  name             = aws_ssm_document.update_peers.name

  targets {
    key    = "tag:aws:autoscaling:groupName"
    values = [aws_autoscaling_group.this.name]
  }

  lifecycle {
    replace_triggered_by = [
      aws_ssm_document.update_peers.latest_version,
      terraform_data.server_conf.input,
    ]
  }
}
