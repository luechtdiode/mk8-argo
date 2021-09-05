# Storybook

*Description of how to setup a single-node cluster using microk8s*

Install Microk8s
----------------
```bash
  sudo snap remove microk8s
  snap info microk8s
  sudo snap install microk8s --classic --channel=1.21/stable
  sudo usermod -a -G microk8s $USER
  sudo chown -f -R $USER ~/.kube
  su - $USER
  microk8s status --wait-ready
  alias kubectl='microk8s kubectl'
  microk8s config > ~/.kube/config
  cd $HOME
  mkdir .kube
  cd .kube
  microk8s config > config
  cd ~/microk8s-setup
  microk8s config > config.admin
  export KUBECONFIG=~/microk8s-setup/admin.config
```

On a remote ssh-client (Dev-System)
-----------------------------------
copy the admin.config to the local dev home for working with kubectl
```bash
scp roland@mars:~/microk8s-setup/admin.config .
export KUBECONFIG=~/admin.config
export KUBECONFIG=/y/docker-apps/mars/mk8-argo/admin.config
```

Edit DNS
--------
add DNS for NodeName
```bash
nano /var/snap/microk8s/current/certs/csr.conf.template
```


Activate plugins
----------------
(use the two ip-addresses of cni1/2 for metallb setup)
```bash
  microk8s enable rbac dns storage ingress dashboard metallb helm3
  sudo snap install kustomize
```

Create admin-user with its sa-token
-----------------------------------
```bash
kubectl apply -f ~/microk8s-setup/admin-user-sa.yaml
kubectl apply -f ~/microk8s-setup/admin-cluster-rolebinding.yaml
kubectl -n kube-system get secret $(kubectl -n kube-system get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}"
```

Make dashboard accessible (optional)
------------------------------------
```bash
kubectl patch svc kubernetes-dashboard -n kube-system -p '{"spec": {"type": "NodePort"}}'
```

Install SealedSecret
--------------------
```bash
cd ~/microk8s-setup/mk8-argo/sealed-secrets
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.16.0/kubeseal-linux-amd64 -O kubeseal

sudo install -m 755 kubeseal /usr/local/bin/kubeseal

helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update
helm dependencies update
# helm install -n kube-system sealed-secrets . -f values.yaml
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.16.0/controller.yaml

cd ../traefik/templates/
printf "mysecret" | base64 -w 0
kubeseal <acme-provider-email-secret.yaml --scope cluster-wide -o yaml >acme-provider-email-sealedsecret.yaml

kubeseal <acme-provider-api-key-secret.yaml --scope cluster-wide -o yaml>acme-provider-api-key-sealedsecret.yaml

kubeseal <acme-provider-api-token-secret.yaml --scope cluster-wide -o yaml >acme-provider-api-token-sealedsecret.yaml
```

*see https://argo-cd.readthedocs.io/en/stable/faq/#why-are-resources-of-type-sealedsecret-stuck-in-the-progressing-state
for solving endless sync-progressig*

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

Install ArgoCD
--------------
* https://github.com/chris-sanders/argocd
* https://chris-sanders.github.io/2020-10-07-argo-in-argo/
* https://operatorhub.io/operator/argocd-operator
* https://www.arthurkoziel.com/setting-up-argocd-with-helm/
* https://rtfm.co.ua/en/argocd-users-access-and-rbac/

Use [GitHub Repo mk8-argo](https://github.com/luechtdiode/mk8-argo) /argo/mootstrap.sh

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
kubeseal <dex-argo-github-secret.yaml -o yaml >dex-argo-github-sealedsecret.yaml
```

### Make ArgoCD Dashboard accessible
```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

Then make it GitOps ready
-------------------------
```bash
kubectl apply -f ~/microk8s-setup/mk8-argo/traefik/apps/traefik-argo-app.yaml
# not ready now kubectl apply -f ~/microk8s-setup/mk8-argo/argo/apps/argocd-app.yaml 
```

Expose Kubernetes Dashboard:
----------------------------
```bash
kubectl apply -n kube-system -f ~/microk8s-setup/mk8-argo/kube-dashboard/kube-dashboard-ingress-route.yaml
```

Install rook-ceph storage
-------------------------
https://github.com/trulede/mk8s_rook
```
kubectl apply -f ~/microk8s-setup/mk8-argo/rook-ceph/apps/rook-ceph-operator-app.yaml
```

Cleanup rook-ceph for reinstall
---------------------
```
. ~/microk8s-setup/mk8-argo/rook-ceph/ceph-cleanup.sh

```