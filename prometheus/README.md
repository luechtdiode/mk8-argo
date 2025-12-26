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