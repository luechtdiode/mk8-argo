#!/bin/bash

alias helm=microk8s.helm3

function askn() {
  read -t 15 -p "$1 (y/N)? " answer
  case "${answer,,}" in
    [Yy]* )
      echo yes
      return 1;
    ;;
    *)
      echo no
      return 0;
  esac
}

function askp() {
  read -t 15 -p "$1 (Y/n)? " answer
  case "${answer,,}" in
    [Nn]* )
      echo no
      return 1;
    ;;
    *)
      echo yes
      return 0;
  esac
}

# namespace deployment
function waitForDeployment() {
  until kubectl wait --for=condition=available deployment/$2 -n $1 --timeout=15s
  do
    if askp "should be waited for readyness of $2 in $1?"
    then
      echo "waiting next 15s ..."
    else
      break;
    fi
  done
}

function mk8_restart() {
  echo "restart microk8s ..."
  sudo snap restart microk8s
  until [ -z "$(sudo microk8s status | grep 'microk8s is not running.')" ]
  do
    echo "waiting until microk8s has started ..."
    sleep 5
  done
}

function cleanupNamespaces() {
  if askp "should argo, sealed-secrets harbor and traefik namespace be cleaned?"
  then
    # cleanup
    helm -n argocd uninstall argocd
    kubectl delete namespace argocd

    helm -n sealed-secrets uninstall sealed-secrets
    kubectl delete namespace sealed-secrets

    helm -n traefik uninstall traefik
    kubectl delete namespace traefik

    helm -n harbor uninstall harbor
    kubectl delete namespace harbor

  fi
}

function installOpenEBSCRD() {
  cd openebs
  helm repo add openebs-zfslocalpv https://openebs.github.io/zfs-localpv
  helm repo update
  helm dependencies update
  helm install -n openebs zfs-localpv openebs-zfslocalpv/zfs-localpv -f values.yaml --create-namespace
  cd ..
}

function installAdmin() {
  kubectl apply -f admin-user-sa.yaml
  kubectl apply -f admin-cluster-rolebinding.yaml
  kubectl -n kube-system get secret $(kubectl -n kube-system get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}"
}

function installSealedSecrets() {
  # sealed-secrets
  cd sealed-secrets
  helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
  helm repo update
  helm dependencies update
  kubectl create namespace sealed-secrets
  helm install -n kube-system sealed-secrets . -f values.yaml
  waitForDeployment kube-system sealed-secrets-controller
  cd ..
}

function restoreSecrets() {
  # restore secrets
  cd backuprestore
  if [[ -z $BACKUP_DATE ]] || [[ ! -d cloud-backup-$BACKUP_DATE ]]; then
    ./main.sh cloudsync down $BACKUP_DATE
  fi
  ./main.sh privatesecretrestore
  cd ..
}

function restoreAppStates() {
  if askp "restore pvcs?"
  then
    cd backuprestore
    ./main.sh restore traefik
    ./main.sh restore harbor
    ./main.sh restore pg-admin
    ./main.sh restore kmgetubs19
    ./main.sh restore kutuapp-test kutuapp-data
    ./main.sh restore kutuapp kutuapp-data
    ./main.sh restore sharevic
    cd ..
  fi
}

function restoreAppDBStates() {
  if askp "restore databases?"
  then
    cd backuprestore
    ./main.sh dbrestore kmgetubs19
    ./main.sh dbrestore kutuapp-test
    ./main.sh dbrestore kutuapp
    cd ..
  fi
}

function installTraefik() {
  # traefik
  cd traefik
  helm repo add traefik https://helm.traefik.io/traefik
  helm repo update
  helm dependencies update

  kubectl create namespace traefik
  helm install -n traefik traefik . -f values.yaml --set templates.skippodmonitor=true

  waitForDeployment traefik traefik
  cd ..
}

function installHarbor() {
  # harbor
  cd harbor
  helm repo add harbor https://helm.goharbor.io
  helm repo update
  helm dependencies update

  kubectl create namespace harbor
  helm install -n harbor harbor . -f values.yaml --set templates.skippodmonitor=true

  waitForDeployment harbor harbor
  cd ..
}

function installArgo() {
  # argocd
  cd argocd
  helm repo add argo-cd https://argoproj.github.io/argo-helm
  helm repo update
  helm dependencies update
  # kubectl apply -k https://github.com/argoproj/argo-cd/manifests/crds\?ref\=v2.9.6
  kubectl create namespace argocd
  helm install -n argocd argocd . -f values.yaml --set installroute=false --set argo-cd.crds.install=true
  waitForDeployment argocd argocd-server
  cd ..
  echo "argocd working now"
}

function boostrapViaArgo() {
  # helm template bootstrap-infra/ | kubectl apply -f -

  helm template bootstrap/ | kubectl apply -f -

  echo "argo-cd works via git-ops now"
  waitForDeployment harbor harbor
  waitForDeployment sharevic sharevic-waf
  waitForDeployment kmgetubs19 odoo11
  waitForDeployment kutuapp-test kutuapp
  waitForDeployment kutuapp kutuapp
  waitForDeployment mbq mbq
}

function setup() {
  cleanupNamespaces
  installSealedSecrets
  restoreSecrets
  #installOpenEBSCRD
  installTraefik
  installHarbor
  installArgo
  boostrapViaArgo
  restoreAppStates
  restoreAppDBStates
}

echo "
  util-script bootstrap.sh
  ------------------------
  usage: source ./bootstrap.sh && setup
  other functions:
    mk8_restart
    cleanupNamespaces
    installSealedSecrets
    restoreSecrets
    installOpenEBSCRD
    installTraefik
    installArgo
    boostrapViaArgo
    restoreAppStates
    restoreAppDBStates
  ------------------------
"