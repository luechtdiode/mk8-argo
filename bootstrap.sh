#!/bin/bash

# cleanup
helm -n argocd uninstall argocd
kubectl delete namespace argocd

helm -n sealed-secrets uninstall sealed-secrets
kubectl delete namespace sealed-secrets

helm -n traefik uninstall traefik
kubectl delete namespace traefik

kubectl apply -f admin-user-sa.yaml
kubectl apply -f admin-cluster-rolebinding.yaml
kubectl -n kube-system get secret $(kubectl -n kube-system get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}"

# sealed-secrets
cd sealed-secrets
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.17.5/kubeseal-0.17.5-linux-amd64.tar.gz -O - | tar xz -C $(pwd)/tmp
sudo install -m 755 tmp/kubeseal /usr/local/bin/kubeseal
rm -rf tmp

helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update
helm dependencies update
kubectl create namespace sealed-secrets
helm install -n kube-system sealed-secrets . -f values.yaml
cd ..

# restore secrets
cd backuprestore
./main.sh cloudsync down
./main.sh privatesecretrestore
./main.sh secretrestore
cd ..

# traefik
cd traefik
helm repo add traefik https://helm.traefik.io/traefik
helm repo update
helm dependencies update

kubectl create namespace traefik
helm install -n traefik traefik/traefik . -f values.yaml
helm upgrade -n traefik traefik/traefik . -f values.yaml
cd ..

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

helm template bootstrap-infra/ | kubectl apply -f -

helm template bootstrap/ | kubectl apply -f -

echo "argo-cd works via git-ops now"
