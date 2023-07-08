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

variable "ssh_authorized_keys" {
  type    = list(string)
  default = []
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

variable "instances" {
  type = map(object({
    ami_filter : string
    instance_types : list(string)
  }))
  default = {
    arm64 : {
      ami_filter : "debian-11-arm64-*"
      instance_types : ["t4g.nano"]
    }
    amd64 : {
      ami_filter : "debian-11-amd64-*"
      instance_types : ["t3.nano"]
    }
  }
}

variable "use_spot_instance" {
  description = "Whether to use spot EC2 instance"
  type        = bool
  default     = true
}

variable "wireguard_port" {
  type    = number
  default = 55820
}

variable "wireguard_private_key" {
  type = string
}

variable "wireguard_wg0_address" {
  type = string
}

variable "wireguard_peers" {
  type = list(object({
    name       = string
    public_key = string
    ip         = string
  }))
}