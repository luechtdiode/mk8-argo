#!/bin/bash

function cleanupNamspaces() {
  # cleanup
  helm -n argocd uninstall argocd
  kubectl delete namespace argocd

  helm -n sealed-secrets uninstall sealed-secrets
  kubectl delete namespace sealed-secrets

  helm -n traefik uninstall traefik
  kubectl delete namespace traefik
}

function installAdmin() {
  kubectl apply -f admin-user-sa.yaml
  kubectl apply -f admin-cluster-rolebinding.yaml
  kubectl -n kube-system get secret $(kubectl -n kube-system get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}"
}

function installSealedSecrets() {
  # sealed-secrets
  cd sealed-secrets
  if [ ! -f /usr/local/bin/kubeseal]; then
    wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.17.5/kubeseal-0.17.5-linux-amd64.tar.gz -O - | tar xz -C $(pwd)/tmp
    sudo install -m 755 tmp/kubeseal /usr/local/bin/kubeseal
    rm -rf tmp
  fi

  helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
  helm repo update
  helm dependencies update
  kubectl create namespace sealed-secrets
  helm install -n kube-system sealed-secrets . -f values.yaml
  cd ..
}

function restoreSecrets() {
  # restore secrets
  cd backuprestore
  ./main.sh cloudsync down
  ./main.sh privatesecretrestore
  ./main.sh secretrestore
  cd ..
}

function restoreAppStates() {
  cd backuprestore
  #./main.sh privatesecretrestore
  ./main.sh restore kmgetubs19
  ./main.sh restore keycloak
  ./main.sh restore kutuapp-test
  ./main.sh restore kutuapp
  ./main.sh restorep sharevic
  cd ..
}

function installTraefik() {
  # traefik
  cd traefik
  helm repo add traefik https://helm.traefik.io/traefik
  helm repo update
  helm dependencies update

  kubectl create namespace traefik
  helm install -n traefik traefik . -f values.yaml --set templates.skippodmonitor=true
  cd ..
}

function installArgo() {
  # argocd
  cd argocd
  helm repo add argo-cd https://argoproj.github.io/argo-helm
  helm repo update
  helm dependencies update
  # kubectl apply -k https://github.com/argoproj/argo-cd/manifests/crds\?ref\=v2.4.4
  kubectl create namespace argocd
  helm install -n argocd argocd . -f values.yaml --set installroute=false
  cd ..

  kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd
  echo "argocd working now"
}

function boostrapViaArgo() {
  # helm template bootstrap-infra/ | kubectl apply -f -

  helm template bootstrap/ | kubectl apply -f -

  echo "argo-cd works via git-ops now"
}

function setup() {
  cd mk8-argo
  cleanupNamspaces
  installSealedSecrets
  restoreSecrets
  installTraefik
  installArgo
  boostrapViaArgo
  restoreAppStates
  cd ..
}

echo $(pwd)

setup
