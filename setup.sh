#!/bin/bash

cat << EOF
Preparation Microk8s Setup
==========================
The following input will be asked by the script:
* ip-range for metallb,                  could be injected by env.NIC_IPS ($NIC_IPS)
* restore from backup at date            could be injected by env.BACKUP_DATE
* csr template variables (cn, dns, ip's)
* storj-accessgrantname,                 could be injected by env.ACCESSNAME
* storj-accessgrant,                     could be injected by env.ACCESSGRANT

usage: bash -i setup.sh

EOF

read -p "press any key to continue ...."

if [ -d mk8-argo ] 
then
  cd mk8-argo
  git pull
  cd ..
else
  git clone -b mk8-126 --single-branch https://github.com/luechtdiode/mk8-argo.git
fi

sudo microk8s stop
wait

# backup existing csr.conf.template conaining local coordinates of the node
[[ -e /var/snap/microk8s/current/certs/csr.conf.template ]] && cp /var/snap/microk8s/current/certs/csr.conf.template csr.conf.template

source ./mk8-argo/createzfspool.sh
source ./mk8-argo/bootstrap.sh

# detach zfspv-pool
zfsDetachPool

# setup micok8s from ground up
installed=$(sudo snap remove microk8s)
echo "$installed"
sudo rm -rf $(pwd)/.kube
mkdir $(pwd)/.kube
sudo chown -f -R $USER $(pwd)/.kube

# install iscsi for openebs storage-drivers
sudo apt-get update
sudo apt-get install open-iscsi
if [[ -z $(systemctl status iscsid | grep 'active (running)') ]]
then
  sudo systemctl enable --now iscsid
fi
wait

if ! [[ installed == '*not installed' ]]
then
  sleep 30s
fi
# snap info microk8s
sudo snap install microk8s --classic --channel=1.26/stable
sudo microk8s status --wait-ready
sudo usermod -a -G microk8s $USER

if [[ -e csr.conf.template ]]
then
  cp /var/snap/microk8s/current/certs/csr.conf.template /var/snap/microk8s/current/certs/csr.conf.template.bak
  cp csr.conf.template /var/snap/microk8s/current/certs/csr.conf.template
else
  nano /var/snap/microk8s/current/certs/csr.conf.template
fi

sudo microk8s refresh-certs --cert ca.crt
sudo microk8s refresh-certs --cert server.crt
sudo microk8s refresh-certs --cert front-proxy-client.crt
sudo microk8s config > ~/.kube/config
admintoken=$(cat ~/.kube/config | grep token:)

echo "alias kubectl='microk8s kubectl'" > ~/.bash_aliases
echo "alias helm='microk8s helm3'" > ~/.bash_aliases
source ~/.bash_aliases
source ~/.bashrc

sudo microk8s enable community
sudo microk8s enable rbac
sudo microk8s enable helm3
sudo microk8s enable dns

mk8_restart

if [ -z "$NIC_IPS" ]; then
  echo "No NIC_IPS for metallb provided. Please interact with the cli ..."
  sudo microk8s enable metallb
else
  echo "Automatic passing $NIC_IPS to metallb ..."
  { echo "$NIC_IPS"; } | sudo microk8s enable metallb
  
  if [ -z "$(kubectl describe IPAddressPool -n metallb-system | grep Name: | awk '{print $2}')" ]
  then    
    until kubectl wait pod -l app=metallb -n metallb-system --for condition=Ready --timeout=180s
    do
      if askp "should be waited for readyness of metal loadbalancer?"
      then
        echo "waiting next 180s ..."
      else
        break;
      fi
    done
    # Create a IP Adresspool
    cat mk8-argo/metallb-system/metallb-ippool.yaml | sed 's|{{ .Values.nic-ips }}|'$NIC_IPS'|g' | kubectl apply -f -
  fi
fi

sudo microk8s enable ingress
sudo microk8s enable metrics-server
#sudo microk8s enable openebs
sudo microk8s enable hostpath-storage
sudo microk8s enable dashboard
wait
sudo microk8s status --wait-ready

until microk8s kubectl wait pod -l k8s-app=kubernetes-dashboard -n kube-system --for condition=Ready --timeout=180s
do
  if askp "should be waited for readyness of kubernetes-dashboard?"
  then
    echo "waiting next 180s ..."
  else
    break;
  fi
done
microk8s kubectl patch svc kubernetes-dashboard -n kube-system -p '{"spec": {"type": "NodePort"}}'

sudo iptables -P FORWARD ACCEPT
sudo ufw allow in on cni0 && sudo ufw allow out on cni0
sudo ufw default allow routed

# install kubeseal
if [ ! -f /usr/local/bin/kubeseal ]; then
  mkdir tmp
  wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.19.3/kubeseal-0.19.3-linux-amd64.tar.gz -O - | tar xz -C $(pwd)/tmp
  sudo install -m 755 tmp/kubeseal /usr/local/bin/kubeseal
  rm -rf tmp
else
  echo kubeseal already installed
fi

# install calicoctl
if [ ! -f /usr/local/bin/calicoctl ]; then
  curl -L https://github.com/projectcalico/calico/releases/download/v3.24.5/calicoctl-linux-amd64 -o calicoctl
  chmod +x ./calicoctl
  sudo install -m 755 calicoctl /usr/local/bin/calicoctl
  rm calicoctl
else
  echo calicoctl already installed
fi

if [[ ! -f ~/.config/storj/uplink/access.json ]]; then
  sudo apt install unzip
  # install storj uplink (interactiv) https://github.com/storj/storj/releases/download/<version or latest>/identity_linux_arm64.zip
  curl -L https://github.com/storj/storj/releases/download/v1.68.2/uplink_linux_amd64.zip -o uplink_linux_amd64.zip
  unzip -o uplink_linux_amd64.zip && rm uplink_linux_amd64.zip
  sudo install -m 755 uplink /usr/local/bin/uplink


  if [ -z "$ACCESSNAME" ] || [ -z "$ACCESSGRANT" ]; then
    echo "No ACCESSNAME and ACCESSGRANT for storj account provided. Please interact with the uplink setup cli ..."
    uplink setup
  else
  { echo 'n'; echo $accessname; echo $accessgrant; echo 'n'; } | uplink setup
  # 1) n            With your permission, Storj can automatically collect analytics information from your uplink CLI to help improve the quality and performance of our products. This information is sent only with your consent and is submitted anonymously to Storj Labs: (y/n)
  # 2) $accessname  Enter name to import as [default: main]:
  # 3) $accessgrant Enter API key or Access grant:
  # 4) n            Would you like S3 backwards-compatible Gateway credentials? (y/N):
  fi
else
  echo uplink already installed
fi

kubectl apply -f ./mk8-argo/admin-user-sa.yaml
kubectl apply -f ./mk8-argo/admin-cluster-rolebinding.yaml

if ! askn "should zfs/zpool be cleared?"
then
  zfsDestroyPool
fi


if ! askn "should zfs/zpool be prepared?"
then
  zfsInitPool
fi

mk8_restart

if askp "should rest of bootstrapping should be executed?"
then
  echo bootstrapping apps ...
  cd mk8-argo
    setup
  cd ..
fi

echo "Admin $admintoken"
echo "Dashboard Service NodePort"
kubectl get svc -n kube-system | grep kubernetes-dashboard