#!/bin/bash

kubectl delete namespace argocd
kubectl create namespace argocd

VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
kubectl delete -f https://raw.githubusercontent.com/argoproj/argo-cd/$VERSION/manifests/install.yaml
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/$VERSION/manifests/install.yaml

echo "login argo-cd with user 'admin' and pw:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

echo "now setting up rbac & sso by github ..."
kubectl apply -n argocd -f templates/argocd-rbac-cm.yaml
kubectl apply -n argocd -f templates/dex-argo-github-sealedsecret.yaml
kubectl -n argocd patch deployment/argocd-dex-server -p "$(cat templates/patch-argocd-dex-deployment.yaml)"
kubectl apply -n argocd -f templates/argocd-cm.yaml

kubectl apply -n argocd -f templates/argocd-server-ingress-route.yaml

kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

echo "... done"