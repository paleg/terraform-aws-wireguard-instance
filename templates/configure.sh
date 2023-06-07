#!/bin/bash -x

apt-get update
apt-get install -y awscli jq locales-all netcat

if ! dpkg -s amazon-ssm-agent &> /dev/null; then
  wget --quiet https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_$(dpkg --print-architecture)/amazon-ssm-agent.deb
  dpkg -i amazon-ssm-agent.deb
  rm -fv amazon-ssm-agent.deb
fi

export AWS_DEFAULT_REGION=${aws_region}
export regular_if=ens5
export eip_if=${eni_if}

# attach the ENI
while :; do
  aws ec2 attach-network-interface \
    --instance-id "$(curl --silent 169.254.169.254/latest/meta-data/instance-id)" \
    --device-index 1 \
    --network-interface-id "${eni_id}"
  [ $? -eq 0 ] && break
  sleep 3
done

# wait for eip address
while :; do
  addr=$(ip -f inet addr show $eip_if | wc -l)
  [ $addr -gt 0 ] && break
  sleep 3
done

via=$(ip route | grep default | awk '{print $3}')
# switch the default route to eip
ip route del default dev $regular_if
ip route add default via $via dev $eip_if

# wait for internet connection
while ! $(nc -w 3 -z 8.8.8.8 53); do
  echo wait
  sleep 3
done

if [ "$(uname -m)" == "aarch64" ]; then
  kernel_suffix="arm64"
else
  kernel_suffix="amd64"
fi
apt-get install -y linux-headers-$kernel_suffix wireguard

modprobe wireguard
sysctl net.ipv4.ip_forward=1

ifup wg0
