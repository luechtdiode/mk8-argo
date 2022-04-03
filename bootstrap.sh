#!/bin/bash

alias kubectl='microk8s kubectl'
alias helm='microk8s helm3'

sudo microk8s config > $(pwd)/../.kube/admin.config
export KUBECONFIG=$(pwd)/../.kube/admin.config

kubectl apply -f admin-user-sa.yaml
kubectl apply -f admin-cluster-rolebinding.yaml
kubectl -n kube-system get secret $(kubectl -n kube-system get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}"

# prepare pre-requisites needed to apply gitops via argocd

cd sealed-secrets
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update
helm dependencies update
kubectl create namespace sealed-secrets
# kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.17.4/controller.yaml
helm install -n kube-system sealed-secrets . -f values.yaml

# kubeseal --fetch-cert \
# --controller-name=sealed-secrets \
# --controller-namespace=sealed-secrets \
# > pub-cert.pem
cd ..

cd backuprestore
./main.sh cloudsync down
./main.sh privatesecretrestore
./main.sh secretrestore
cd ..

cd traefik
helm repo add traefik https://helm.traefik.io/traefik
helm repo update
helm dependencies update

kubectl create namespace traefik
helm install -n traefik traefik/traefik . -f values.yaml
cd ..

cd argocd
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm repo update
helm dependencies update

kubectl create namespace argocd
helm install -n argocd argocd . -f values.yaml --set install-route=false
cd ..

kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

echo "argocd working now"

helm template bootstrap-infra/ | kubectl apply -f -

helm template bootstrap/ | kubectl apply -f -

echo "argo-cd works via git-ops now"