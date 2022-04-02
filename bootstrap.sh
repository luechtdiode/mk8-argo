#!/bin/bash

# setup micok8s from ground up
sudo snap remove microk8s
rm -rf $(pwd)/.kube
mkdir $(pwd)/.kube
sudo chown -f -R $USER $(pwd)/.kube

sudo apt-get update
sudo apt-get install open-iscsi
sudo systemctl enable --now iscsid
sudo cat /etc/iscsi/initiatorname.iscsi
systemctl status iscsid

snap info microk8s
sudo snap install microk8s --classic --channel=latest/stable
sudo usermod -a -G microk8s $USER
# su - $USER
sudo microk8s status --wait-ready
sudo microk8s enable helm3 host-access ingress metrics-server dns openebs rbac storage
sudo iptables -P FORWARD ACCEPT

alias kubectl='microk8s kubectl'
alias helm='microk8s helm3'

microk8s config > $(pwd)/.kube/admin.config
export KUBECONFIG=$(pwd)/.kube/admin.config

# prepare pre-requisites needed to apply gitops via argocd

cd sealed-secrets
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.16.0/kubeseal-linux-amd64 -O kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update
helm dependencies update
helm install sealed-secrets sealed-secrets/sealed-secrets
cd ..

sudo apt install unzip
curl -L https://github.com/storj/storj/releases/latest/download/uplink_linux_amd64.zip -o uplink_linux_amd64.zip
unzip -o uplink_linux_amd64.zip && rm uplink_linux_amd64.zip
sudo install -m 755 uplink /usr/local/bin/uplink
uplink setup # 2 eu1.storj.io, access-name, api-key, passphrase, passphrase, n


cd backuprestore
./main.sh cloudsync down
./main.sh secretrestore
cd ..

cd traefik
helm repo add traefik https://helm.traefik.io/traefik
helm repo update
helm dependencies update
helm template traefik traefik/traefik -f values.yaml --debug
kubectl delete namespace traefik
kubectl create namespace traefik
helm install -n traefik traefik/traefik . -f values.yaml
helm upgrade -n traefik traefik/traefik . -f values.yaml
cd ..

cd argocd
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm repo update
helm dependencies update
helm template argocd . -f values.yaml --debug

kubectl create namespace argocd
helm install -n argocd argocd . -f values.yaml
helm upgrade -n argocd argocd . -f values.yaml
cd ..

kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

echo "argocd working now"

helm template bootstrap/ | kubectl apply -f -

echo "argo-cd works via git-ops now"