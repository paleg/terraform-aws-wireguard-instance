resource "tls_private_key" "host_rsa" {
  algorithm = "RSA"
  rsa_bits = 4096
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
      eni_id     = aws_network_interface.this.id,
      eni_if     = "ens6",
      aws_region = data.aws_region.current.name,
    }
  )

  wg0 = templatefile(
    "${path.module}/templates/wg0",
    {
      eni_if = "ens6",
    }
  )

  server_conf = templatefile(
    "${path.module}/templates/server.conf",
    {
      server_private_key = var.wireguard_private_key,
      server_port        = var.wireguard_port,
      peers              = var.wireguard_peers,
    }
  )
}

data "cloudinit_config" "this" {
  gzip          = false
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content      = <<EOF
#!/bin/bash

set -x

umask 077
rm /etc/ssh/*.pub
rm /etc/ssh/ssh_host_dsa_key
echo '${tls_private_key.host_ecdsa.private_key_pem}' >/etc/ssh/ssh_host_ecdsa_key
echo '${tls_private_key.host_ed25519.private_key_pem}' >/etc/ssh/ssh_host_ed25519_key
echo '${tls_private_key.host_rsa.private_key_pem}' >/etc/ssh/ssh_host_rsa_key
systemctl restart sshd
EOF
  }

  part {
    content_type = "text/cloud-config"
    content      = yamlencode(
{
  write_files: [
    {
      path: "/tmp/configure.sh",
      content: local.configure_sh,
      permissions: "0755"
    },
    {
      path: "/etc/network/interfaces.d/wg0"
      content: local.wg0,
      permissions: "0755",
    },
    {
      path: "/etc/wireguard/server.conf",
      content: local.server_conf,
      permissions: "0755",
    }
  ]
}
    )
  }

  part {
    content_type = "text/cloud-config"
    content = <<EOF
runcmd:
  - ["/tmp/configure.sh"]
EOF
  }
}
