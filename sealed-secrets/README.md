Install SealedSecret
--------------------

```bash
cd ~/microk8s-setup/mk8-argo/sealed-secrets

# get kubeseal, extract and install
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.19.3/kubeseal-0.19.3-linux-amd64.tar.gz -O - | tar xz -C $(pwd)/tmp
sudo install -m 755 tmp/kubeseal /usr/local/bin/kubeseal
rm -rf tmp

helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update
helm dependencies update
kubectl create namespace sealed-secrets
helm install -n kube-system sealed-secrets . -f values.yaml

kubeseal --fetch-cert  > pub-cert.pem

cd ..
```
