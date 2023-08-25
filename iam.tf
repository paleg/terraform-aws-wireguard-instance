module "iam_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  version = "~> v5.25"

  create_role = true

  role_name         = var.name
  role_requires_mfa = false

  create_instance_profile = true

  trusted_role_services = ["ec2.amazonaws.com"]
  trusted_role_actions  = ["sts:AssumeRole"]

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    aws_iam_policy.eni.arn,
  ]
}

resource "aws_iam_policy" "eni" {
  name   = var.name
  policy = data.aws_iam_policy_document.eni.json
}

data "aws_iam_policy_document" "eni" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:AttachNetworkInterface"
    ]
    resources = [
      aws_network_interface.this.arn
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "ec2:AttachNetworkInterface"
    ]
    resources = [
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "ec2:InstanceProfile"
      values = [
        module.iam_role.iam_instance_profile_arn
      ]
    }
  }
}
