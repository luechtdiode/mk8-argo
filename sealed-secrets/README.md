Install SealedSecret
--------------------

```bash
cd ~/microk8s-setup/mk8-argo/sealed-secrets
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.17.5/kubeseal-0.17.5-linux-amd64.tar.gz -O kubeseal

sudo install -m 755 kubeseal /usr/local/bin/kubeseal

helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update
helm dependencies update
```
