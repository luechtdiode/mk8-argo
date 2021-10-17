Install rook-ceph storage
-------------------------
https://github.com/trulede/mk8s_rook
*actually, unresolved reboot-osd-failures*
https://github.com/rook/rook/issues/7519
https://github.com/ceph/ceph-ansible/issues/2354
```
kubectl apply -f ~/microk8s-setup/mk8-argo/rook-ceph/apps/rook-ceph-operator-app.yaml
```
https://s3-website.cern.ch/cephdocs/ops/create_a_cluster_short.html
https://github.com/el95149/vagrant-microk8s-ceph/tree/master/cookbooks/common
https://jonathangazeley.com/2020/09/10/building-a-hyperconverged-kubernetes-cluster-with-microk8s-and-ceph/
https://www.youtube.com/watch?v=4JRYIEH_1DM

Cleanup rook-ceph for reinstall
---------------------
```
. ~/microk8s-setup/mk8-argo/rook-ceph/ceph-cleanup.sh

```