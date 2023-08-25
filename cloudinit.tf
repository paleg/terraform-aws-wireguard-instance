resource "tls_private_key" "host_rsa" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
resource "tls_private_key" "host_ecdsa" {
  algorithm = "ECDSA"
}

resource "tls_private_key" "host_ed25519" {
  algorithm = "ED25519"
}

locals {
  configure_sh = templatefile(
    "${path.module}/templates/configure.sh",
    {
      eni_id : aws_network_interface.this.id
      eni_if : "ens6"
      aws_region : data.aws_region.current.name
      server_conf_secret_name : module.secretsmanager_secret_server_conf.secret_id
      server_conf_path : local.server_conf_path
    }
  )

  wg0 = templatefile(
    "${path.module}/templates/wg0",
    {
      eni_if : "ens6"
      wireguard_wg0_address : var.wireguard_wg0_address
      server_conf_path : local.server_conf_path
    }
  )


  server_conf_path        = "/etc/wireguard/server.conf"
  server_conf_secret_name = "${var.name}/server.conf"

  server_conf = templatefile(
    "${path.module}/templates/server.conf",
    {
      server_private_key : var.wireguard_private_key
      server_port : var.wireguard_port
      peers : var.wireguard_peers
    }
  )
}

data "cloudinit_config" "this" {
  gzip          = false
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = templatefile(
      "${path.module}/templates/cloud-config.yaml",
      {
        ssh_keys : {
          rsa_private : tls_private_key.host_rsa.private_key_pem
          rsa_public : tls_private_key.host_rsa.public_key_openssh
          ecdsa_private : tls_private_key.host_ecdsa.private_key_pem
          ecdsa_public : tls_private_key.host_ecdsa.public_key_openssh
          ed25519_private : tls_private_key.host_ed25519.private_key_pem
          ed25519_public : tls_private_key.host_ed25519.public_key_openssh
        }
        ssh_authorized_keys : var.ssh_authorized_keys
        configure_sh : local.configure_sh
        wireguard_wg0_conf : local.wg0
      }
    )
  }

  part {
    content_type = "text/cloud-config"
    content      = <<EOF
runcmd:
  - ["/tmp/configure.sh"]
EOF
  }
}
