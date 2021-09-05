#!/bin/bash

# ceph-volume library required.
# use via toolbox in kubernetes, or direct installed in host-os:
# sudo apt install ceph-osd

for CRD in $(kubectl get crd -n rook-ceph | awk '/ceph.rook.io/ {print $1}'); do
    kubectl get -n rook-ceph "$CRD" -o name | \
    xargs -I {} kubectl patch -n rook-ceph {} --type merge -p '{"metadata":{"finalizers": [null]}}'
done

kubectl delete namespace rook-ceph

sudo rm -rf /var/lib/rook

lsblk -f
DISK="/dev/sdb"
sudo ceph-volume lvm zap --destroy $DISK

# alternative (not working, keeps sdb locked)
# sudo sgdisk --zap-all $DISK
# sudo dd if=/dev/zero of="$DISK" bs=1M count=100 oflag=direct,dsync
# sudo rm -rf /dev/ceph-*
# sudo rm -rf /dev/mapper/ceph--*
# sudo partprobe $DISK