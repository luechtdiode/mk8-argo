#!/bin/bash

# https://docs.oracle.com/cd/E23824_01/html/821-1448/recover-1.html#scrolltoc

ZFS_POOL=zfs-pvpool

function zfs_backup() {
  namespace=$1
  TARGET=$2
  pvc=$3

  sed "s/pvcname/$pvc/g" zfs-snapshot.yaml | kubectl -n $namespace apply -f -
  sed "s/pvcname/$pvc/g" zfs-snapshot.yaml | kubectl -n $namespace wait --for=condition=readytouse=true VolumeSnapshot apply -f -

  kubectl -n $namespace get volumesnapshot.snapshot
  snapshots=$(kubectl -n $namespace  get volumesnapshot.snapshot -o jsonpath='{.items[?(@.status.readyToUse==true)].status.boundVolumeSnapshotContentName}')
  for snapshot in $snapshots | xargs do;
    zfs send -Rv "${ZFS_POOL}/${pvc}@${snapshot}" | gzip > $TARGET/$snapshot
  done
}

function zfs_restore() {
  namespace=$1
  pvc=kubectl -n $namespace get volumesnapshot.snapshot -o jsonpath='{.items[*].spec.source.persistentVolumeClaimName}'
  snapshots=$(kubectl -n $namespace get volumesnapshot.snapshot -o jsonpath='{.items[*].status.boundVolumeSnapshotContentName}')

  for snapshot in $snapshots | xargs do;
    gzcat $TARGET/$snapshot | zfs receive -Fv "${ZFS_POOL}/${pvc}@${snapshot}"
  done
}
