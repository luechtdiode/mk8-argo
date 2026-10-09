Install ArgoCD
--------------
* https://github.com/chris-sanders/argocd
* https://chris-sanders.github.io/2020-10-07-argo-in-argo/
* https://operatorhub.io/operator/argocd-operator
* https://www.arthurkoziel.com/setting-up-argocd-with-helm/
* https://rtfm.co.ua/en/argocd-users-access-and-rbac/
* https://www.arthurkoziel.com/setting-up-argocd-with-helm/

Use [GitHub Repo mk8-argo](https://github.com/luechtdiode/mk8-argo) /bootstrap.sh

### Grab Admin-Secret if admin-account is enabled
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### (optional) local admin tooling
```bash
sudo curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64
sudo chmod +x /usr/local/bin/argocd
```

### Create SealedSecred, used to integrate github OAUTH2
```bash
kubeseal <argocd-dex-github-secret.yaml -o yaml >argocd-dex-github-sealedsecret.yaml
```

### Make ArgoCD Dashboard accessible
```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

### relax sync-checks of SealedSecrets
*see https://argo-cd.readthedocs.io/en/stable/faq/#why-are-resources-of-type-sealedsecret-stuck-in-the-progressing-state
for solving endless sync-progressig*

### upgrade ArgoCD CRD's
before applying new ArgoCD version, ensure to apply the CRDs first, otherwise ArgoCD will not start and will be stuck in a crashloop.
1) Ensure Helm repo is up to date
```bash
helm repo add argo-cd https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update
```
2) Apply CRDs for argo-cd 10.10.1 with server-side apply
   Use one of these (both extract CRDs from the new chart version). Server-side apply with --force-conflicts is required (ApplicationSet CRD is large).
   Option A (stream directly):
```bash
helm template argo-cd argo-cd/argo-cd --version 10.10.1 --namespace argocd --include-crds --set crds.install=true \
  | kubectl apply --server-side --force-conflicts -f -
```
Option B (save to file first, inspect if desired):
```bash
helm show crds argo-cd/argo-cd --version 10.10.1 > /tmp/crds-argo-cd-10.10.1.yaml
kubectl apply --server-side --force-conflicts -f /tmp/crds-argo-cd-10.10.1.yaml
```