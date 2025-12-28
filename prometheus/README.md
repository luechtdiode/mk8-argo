# Prometheus-Community Helm Setup

Add Repo
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
```

List Charts
```bash
helm search repo prometheus-community
```

Search for
* kube-prometheus-stack
* prometheus-blackbox-exporter

and update versions in the [Chart](./Chart.yaml).


### Upgrade
```bash
  helm search repo prometheus-community
  # Update Chart-Version in Chart.yaml to latest version, e.g. 38.0
  # 1. Download and install the new CRDs manually FIRST
  kubectl apply -f https://raw.githubusercontent.com/xxx.yaml
  # then simulate upgrade:
  helm repo update
  helm dependencies update
  helm lint .
  hhelm template -n prometheus prometheus . --values values.yaml --validate
  helm  upgrade -n prometheus prometheus . --dry-run --debug --values values.yaml
  # If no errors, perform upgrade by argo-cd.
```
