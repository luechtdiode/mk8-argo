Install Harbor
==============

Add Helm repository
```bash
helm repo add harbor https://helm.goharbor.io
helm repo update
helm dependencies update
helm template harbor harbor/harbor -f values.yaml --debug
kubectl delete namespace harbor
kubectl create namespace harbor
helm install -n harbor harbor/harbor . -f values.yaml
```

Download values.yaml
```https://raw.githubusercontent.com/goharbor/harbor-helm/main/values.yaml```

Replace 
`core.harbor.domain` with `harbor.interpolar.ch`
`tag:` with `# tag:`

Create harbor admin secret
```bash
kubectl create secret generic harbor-user-secret --from-literal=HARBOR_ADMIN_PASSWORD=$(head -c 16 /dev/urandom | base64) --dry-run=client -o yaml > harbor-user-secret.yaml
kubeseal <harbor-user-secret.yaml -n harbor -o yaml >harbor-user-sealedsecret.yaml
```