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

### Upgrade
```bash
  helm search repo traefik
  # Update Chart-Version in Chart.yaml to latest version, e.g. 38.0
  # 1. Download and install the new CRDs manually FIRST
  kubectl apply -f https://raw.githubusercontent.com/traefik/traefik-helm-chart/v38.0.1/traefik/crds/traefik.io_ingressroutes.yaml
  kubectl apply -f https://raw.githubusercontent.com/traefik/traefik-helm-chart/v38.0.1/traefik/crds/traefik.io_middlewares.yaml
  kubectl apply -f https://raw.githubusercontent.com/traefik/traefik-helm-chart/v38.0.1/traefik/crds/traefik.io_tlsstores.yaml
  # then simulate upgrade:
  helm lint .
  helm template traefik . --values values.yaml --validate --set templates.skippodmonitor=true --set traefik.serviceAccount.name=""
  helm  upgrade -n traefik traefik . --dry-run --debug --values values.yaml --set templates.skippodmonitor=true --set traefik.serviceAccount.name=""
  # If no errors, perform upgrade by argo-cd.
```

### ArgoCD Resync

```bash
kubectl rollout restart deployment traefik -n traefik
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
