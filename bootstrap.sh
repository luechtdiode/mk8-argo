#!/bin/bash

helm -n argocd uninstall argocd
kubectl delete namespace argocd

helm -n sealed-secrets uninstall sealed-secrets
kubectl delete namespace sealed-secrets

helm -n traefik uninstall traefik
kubectl delete namespace traefik

cd sealed-secrets
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update
helm dependencies update
helm install -n sealed-secrets . -f values.yaml
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