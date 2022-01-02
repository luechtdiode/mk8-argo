#!/bin/bash

namespace=$1
pvc=$2

sed 's/pvcname/$pvc/g' zfs-snapshot.yaml | kubectl -n $namespace apply -f -
sed 's/pvcname/$pvc/g' zfs-snapshot.yaml | kubectl -n $namespace wait --for=condition=readytouse=true VolumeSnapshot apply -f -

kubectl -n $namespace get volumesnapshot.snapshot
