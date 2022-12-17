#!/bin/bash

# start with sudo bash -i setup-microk8s-vm.sh

git clone https://github.com/luechtdiode/mk8-argo.git
git checkout master

# setup micok8s from ground up
# sudo snap remove microk8s
mkdir $(pwd)/.kube
sudo chown -f -R $USER $(pwd)/.kube

# install iscsi for openebs storage-drivers
sudo apt-get update
sudo apt-get install open-iscsi
sudo systemctl enable --now iscsid
# sudo cat /etc/iscsi/initiatorname.iscsi
systemctl status iscsid

# snap info microk8s
sudo snap install microk8s --classic --channel=1.23/stable
sudo microk8s status --wait-ready

#sudo microk8s refresh-certs --cert ca.crt
#sudo microk8s refresh-certs --cert server.crt
#sudo microk8s refresh-certs --cert front-proxy-client.crt
sudo microk8s config > .kube/config

sudo microk8s enable community
sudo microk8s enable rbac helm3 dns ingress metrics-server storage openebs dashboard
sudo microk8s status --wait-ready
sudo microk8s enable dashboard
sudo microk8s status --wait-ready
kubectl patch svc kubernetes-dashboard -n kube-system -p '{"spec": {"type": "NodePort"}}'

sudo iptables -P FORWARD ACCEPT
sudo usermod -a -G microk8s $USER
# newgrp microk8s
# su - $USER

echo "alias kubectl='microk8s kubectl'" > ~/.bash_aliases
echo "alias helm='microk8s helm3'" > ~/.bash_aliases
source ~/.bash_aliases
source ~/.bashrc

sudo ufw allow in on cni0 && sudo ufw allow out on cni0
sudo ufw default allow routed

# install kubeseal
mkdir tmp
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.17.5/kubeseal-0.17.5-linux-amd64.tar.gz -O - | tar xz -C $(pwd)/tmp
sudo install -m 755 tmp/kubeseal /usr/local/bin/kubeseal
rm -rf tmp

# install calicoctl
curl -L https://github.com/projectcalico/calico/releases/download/v3.24.5/calicoctl-linux-amd64 -o calicoctl
chmod +x ./calicoctl
sudo install -m 755 calicoctl /usr/local/bin/calicoctl
rm calicoctl

# install storj uplink (interactiv) https://github.com/storj/storj/releases/download/v1.61.1/identity_linux_arm64.zip
#sudo apt install unzip
#curl -L https://github.com/storj/storj/releases/latest/download/uplink_linux_amd64.zip -o uplink_linux_amd64.zip
#unzip -o uplink_linux_amd64.zip && rm uplink_linux_amd64.zip
#sudo install -m 755 uplink /usr/local/bin/uplink
#uplink setup # 2 eu1.storj.io, access-name, api-key, passphrase, passphrase, n

cd mk8-argo

sudo bash -i ./bootstrap.sh
