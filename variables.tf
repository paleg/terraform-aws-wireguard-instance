variable "name" {
  type = string
}

variable "vpc_id" {
  type    = string
  default = null
}

variable "subnet_id" {
  type    = string
  default = null
}

variable "pub_key" {
  type    = string
  default = null
}

variable "admin_locations" {
  type = list(string)
}

variable "enabled" {
  type    = bool
  default = true
}

variable "ami_owner" {
  type    = string
  default = "903794441882"
}
variable "ami_filter" {
  type    = string
  default = "debian-11-arm64-*"
}

variable "instance_types" {
  type    = list(string)
  default = ["t4g.nano"]
}

variable "use_spot_instance" {
  description = "Whether to use spot EC2 instance"
  type        = bool
  default     = true
}

variable "ssm_policy_arn" {
  description = "SSM Policy to be attached to instance profile"
  type        = string
  default     = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

variable "wireguard_port" {
  type    = number
  default = 55820
}

variable "wireguard_private_key" {
  type = string
}

variable "wireguard_peers" {
  type = list(object({
    name       = string
    public_key = string
    ip         = string
  }))
}