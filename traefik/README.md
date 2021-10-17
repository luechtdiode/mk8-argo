Install Traefik
---------------
*https://traefik.io/blog/install-and-configure-traefik-with-helm/*
*https://github.com/traefik/traefik-helm-chart/blob/master/traefik/values.yaml*
### Initial Setup without ArgoCD:
```bash
helm repo add traefik https://helm.traefik.io/traefik
helm repo update
helm dependencies update
helm template traefik traefik/traefik -f values.yaml --debug
kubectl delete namespace traefik
kubectl create namespace traefik
helm install -n traefik traefik/traefik . -f values.yaml
helm upgrade -n traefik traefik/traefik . -f values.yaml
kubectl apply -f ~/microk8s-setup/mk8-argo/traefik/apps/traefik-argo-app.yaml
```

Create Sealed Secrets for Traefik-Namespace
-------------------------------------------
```
printf "mysecret" | base64 -w 0
kubeseal <acme-provider-email-secret.yaml --scope cluster-wide -o yaml >acme-provider-email-sealedsecret.yaml

kubeseal <acme-provider-api-key-secret.yaml --scope cluster-wide -o yaml>acme-provider-api-key-sealedsecret.yaml

kubeseal <acme-provider-api-token-secret.yaml --scope cluster-wide -o yaml >acme-provider-api-token-sealedsecret.yaml

kubeseal <traefik-dashboard-user-secret.yaml -o yaml >traefik-dashboard-user-sealedsecret.yaml
```
