#!/bin/bash

helm -n argocd uninstall argocd
kubectl delete namespace argocd

helm repo add argo-cd https://argoproj.github.io/argo-helm
helm repo update
helm dependencies update
helm template argocd argocd/. -f argocd/values.yaml --debug

kubectl create namespace argocd
helm install -n argocd argocd argocd/. -f argocd/values.yaml
helm upgrade -n argocd argocd argocd/. -f argocd/values.yaml

kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

echo "argocd working now"

helm template bootstrap/ | kubectl apply -f -

echo "argo-cd works via git-ops now"