#!/bin/bash

git clone https://github.com/luechtdiode/mk8-argo.git
git checkout mbp

# setup micok8s from ground up
# sudo snap remove microk8s
mkdir $(pwd)/.kube
sudo chown -f -R $USER $(pwd)/.kube

# install iscsi for openebs storage-drivers
sudo apt-get update
sudo apt-get install open-iscsi
sudo systemctl enable --now iscsid
# sudo cat /etc/iscsi/initiatorname.iscsi
# systemctl status iscsid

# snap info microk8s
sudo snap install microk8s --classic --channel=latest/stable
sudo microk8s status --wait-ready
sudo microk8s enable rbac helm3 dns ingress metrics-server storage host-access openebs
sudo iptables -P FORWARD ACCEPT
sudo usermod -a -G microk8s $USER
# newgrp microk8s
# su - $USER

# install kubeseal
mkdir tmp
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.17.4/kubeseal-0.17.4-linux-amd64.tar.gz -O - | tar xz -C $(pwd)/tmp
sudo install -m 755 tmp/kubeseal /usr/local/bin/kubeseal
rm -rf tmp

# install storj uplink (interactiv)
sudo apt install unzip
curl -L https://github.com/storj/storj/releases/latest/download/uplink_linux_amd64.zip -o uplink_linux_amd64.zip
unzip -o uplink_linux_amd64.zip && rm uplink_linux_amd64.zip
sudo install -m 755 uplink /usr/local/bin/uplink
uplink setup # 2 eu1.storj.io, access-name, api-key, passphrase, passphrase, n

cd mk8-argo

./bootstrap.sh