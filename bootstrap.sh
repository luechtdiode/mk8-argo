#!/bin/bash

#alias helm=microk8s.helm3
function helm() {
  sudo microk8s.helm3 "$@"
}

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

    rm -f original-containerd-template.toml
    rm -f original-dockerio-host.toml
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
  kubectl apply -f admin-user-secret-accesstoken.yaml
  sleep 10
  #kubectl -n kube-system get secret $(kubectl -n kube-system get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}"
  kubectl -n kube-system get secret admin-user-secret -o go-template="{{.data.token | base64decode}}"
}

function getKubeAdminToken() {
  kubectl -n kubernetes-dashboard get secret admin-user -o go-template="{{.data.token | base64decode}}"
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

function restorePreArgoAppStates() {
  if askp "restore pre argo apps (traefik, harbor) pvcs?"
  then
    cd backuprestore
    ./main.sh restore traefik
    # ./main.sh restore harbor
    cd ..
  fi
}
function restoreAppStates() {
  if askp "restore pvcs?"
  then
    cd backuprestore
    ./main.sh restore traefik
    ./main.sh restore pg-admin
    ./main.sh restore kmgetubs19
    ./main.sh restore kutuapp-test kutuapp-data
    ./main.sh restore kutuapp kutuapp-data
    ./main.sh restore sharevic
    ./main.sh restore adventscalendar-test
    ./main.sh restore adventscalendar
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
    ./main.sh dbrestore adventscalendar-test
    ./main.sh dbrestore adventscalendar
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
  helm install -n traefik traefik . -f values.yaml --set templates.skippodmonitor=true --set traefik.serviceAccount.name=""

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
  helm install -n harbor harbor . -f values.yaml

  waitForDeployment harbor harbor-registry
  waitForDeployment harbor harbor-core
  waitForDeployment harbor harbor-portal
  waitForDeployment harbor harbor-jobservice
  cd ..
}

function extractDockerSecretsImpl() {
    sudo cp /var/snap/microk8s/current/args/containerd-template.toml original-containerd-template.toml
    sudo cp original-containerd-template.toml containerd-template.toml
    kubectl apply -f docker-registry-sealedsecret.yaml
    
    secret="$(kubectl get secret docker-registry-secret -o jsonpath="{.data.\.dockerconfigjson}" | base64 --decode)"
    while [ -z "$secret" ]
    do
      echo "wait for existing docker-registry-secret ($secret)"
      sleep 10
      secret="$(kubectl get secret docker-registry-secret -o jsonpath="{.data.\.dockerconfigjson}" | base64 --decode)"
    done
    username=$(echo $secret | jq .[][].username)
    password=$(echo $secret | jq .[][].password)
    plugins='plugins."io.containerd.grpc.v1.cri".registry.configs."registry-1.docker.io".auth'
    #harbor=$(kubectl -n harbor get secret harbor-user-secret -o go-template="{{.data.HARBOR_ADMIN_PASSWORD | base64decode}}")
    sudo echo """
  [$plugins]
    username = $username
    password = $password

  #[plugins."io.containerd.grpc.v1.cri".registry.configs."harbor.interpolar.ch:8443".auth]
  #  username = "admin"
  #  password = "$harbor"e
  
  #[plugins."io.containerd.grpc.v1.cri".registry.mirrors]
  #  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."harbor.interpolar.ch"]
  #    endpoint = ["https://harbor.interpolar.ch:8443", ]    
""" >> containerd-template.toml
    sudo cp containerd-template.toml /var/snap/microk8s/current/args/containerd-template.toml
    mk8_restart
}

function extractDockerSecrets() {
  if [[ -e original-containerd-template.toml ]]
  then
    sudo cat /var/snap/microk8s/current/args/containerd-template.toml
    if ! askn "hopefully, the creds are set already. Should they be added manually?"
    then
      extractDockerSecretsImpl
    fi
  else
    extractDockerSecretsImpl
  fi
}

function toggleHarborMirror() {
  if [[ -e original-dockerio-host.toml ]]
  then
    cp original-dockerio-host.toml /var/snap/microk8s/current/args/certs.d/docker.io/hosts.toml
    rm -f ./original-dockerio-host.toml

    sudo microk8s stop
    sudo microk8s start
    waitForDeployment traefik traefik
    waitForDeployment harbor harbor-registry
    waitForDeployment harbor harbor-core
    waitForDeployment harbor harbor-portal
    waitForDeployment harbor harbor-jobservice
  elif ! askn "Should harbor-mirror be used fom now on?"
  then
    cp /var/snap/microk8s/current/args/certs.d/docker.io/hosts.toml ./original-dockerio-host.toml
    nano harbor-mirror-host.toml
    cp harbor-mirror-host.toml /var/snap/microk8s/current/args/certs.d/docker.io/hosts.toml

    sudo microk8s stop
    sudo microk8s start
    waitForDeployment traefik traefik
    waitForDeployment harbor harbor-registry
    waitForDeployment harbor harbor-core
    waitForDeployment harbor harbor-portal
    waitForDeployment harbor harbor-jobservice
  fi
}

function installMinio() {
  cd minio-operator
  sudo microk8s enable minio
  kubectl apply -f routes.yaml
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
  waitForDeployment traefik traefik
  waitForDeployment sharevic sharevic-waf
  waitForDeployment kmgetubs19-static kmgetubs19
  waitForDeployment kutuapp-test kutuapp
  waitForDeployment kutuapp kutuapp
  waitForDeployment mbq mbq
}

function setup() {
  cleanupNamespaces
  installSealedSecrets
  restoreSecrets
  extractDockerSecrets
  #installOpenEBSCRD
  installTraefik
  #installHarbor
  restorePreArgoAppStates
  #toggleHarborMirror
  installArgo
  boostrapViaArgo
  restoreAppStates
  restoreAppDBStates
  installMinio
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
    extractDockerSecrets
    installOpenEBSCRD
    installTraefik
    installHarbor
    toggleHarborMirror
    installArgo
    boostrapViaArgo
    restoreAppStates
    restoreAppDBStates
    installMinio
  ------------------------
"
