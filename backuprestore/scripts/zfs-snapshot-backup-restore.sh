#!/bin/bash

# https://docs.oracle.com/cd/E23824_01/html/821-1448/recover-1.html#scrolltoc

ZFS_POOL=zfspv-pool

# zfs_backup $namespace $pvcname $BACKUP_DIR
function zfs_backup() {
  namespace=$1
  pvc=$2
  TARGET=$3
  
  mkdir -p ${TARGET}

  volumename=$(kubectl get persistentvolumeclaims $pvc -n $namespace -o=jsonpath='{ ..volumeName }')
  echo "creating snapshot for namespace $namespace, pvc $pvc from volume $volumename"  

  existingsnapshots=($(kubectl -n $namespace get volumesnapshot.snapshot -o jsonpath='{.items[*].status.boundVolumeSnapshotContentName}'))
  number=$(echo $(expr "${#existingsnapshots[@]}" + 1))
  echo "next snapshot-number should be $number"

  snap=($(sed -e "s/pvcname/$pvc/g" -e "s/zfspv-snapname/snap-$number/g" scripts/zfs-snapshot.yaml | kubectl -n $namespace apply -f -)[0])
  echo "Snapshot creation submitted: $snap"

  # kubectl -n $namespace $snap wait --for=condition=jsonpath="{.status.readyToUse}"
  ready=$(kubectl -n $namespace get $snap -o jsonpath="{.status.readyToUse}")
  
  while [ $ready != "true" ]
  do
    echo "snapshot not ready yet, wait another 1 seconds ..."
    sleep 1
    ready=$(kubectl -n $namespace get $snap -o jsonpath="{.status.readyToUse}")
  done
  echo "Snapshot is ready: $ready"

  volumesnapshots=$(kubectl -n $namespace get volumesnapshot.snapshot -o jsonpath="{.items[?(@.spec.source.persistentVolumeClaimName=='$pvc')].status.boundVolumeSnapshotContentName}")

  for volumesnapshot in $volumesnapshots
  do
    backupfile=$TARGET/${volumesnapshot}.gz
    if [ ! -f "$backupfile" ]; then
      zfssnapshotname=$(echo $volumesnapshot | sed "s/snapcontent-/snapshot-/g")
      echo "taking zfs backup for $pvc/$volumesnapshot from ${ZFS_POOL}/${volumename}@${zfssnapshotname}) to $backupfile ..."
      sudo zfs send -cv "${ZFS_POOL}/${volumename}@${zfssnapshotname}" | gzip > $backupfile
      #sudo zfs send -Rcv "${ZFS_POOL}/${volumename}@${zfssnapshotname}" | gzip > $backupfile
    else 
      echo "zfs backup $backupfile already exists for $volumesnapshot/$zfssnapshotname (${ZFS_POOL}/${volumename}@${zfssnapshotname})..."
    fi
  done
}

# zfs_restore $namespace $pvcname $BACKUP_DIR
function zfs_restore() {
    namespace=$1
    pvc=$2 #kubectl -n $namespace get volumesnapshot.snapshot -o jsonpath='{.items[*].spec.source.persistentVolumeClaimName}'
    BACKUP_DIR=$3
    volumename=$(kubectl get persistentvolumeclaims $pvc -n $namespace -o=jsonpath='{ ..volumeName }')
    volumesnapshots=$(kubectl -n $namespace get volumesnapshot.snapshot -o jsonpath='{.items[*].status.boundVolumeSnapshotContentName}')
    echo "restoring $volumename with snapshots: $volumesnapshots"

    for volumesnapshot in $volumesnapshots
    do
      backupfile=$BACKUP_DIR/${volumesnapshot}.gz
      if [ -f "$backupfile" ]; then
        zfssnapshotname=$(echo $volumesnapshot | sed "s/snapcontent-/snapshot-/g")
        echo "restoring zfs backup for $pvc/$volumesnapshot from $backupfile  to (${ZFS_POOL}/${volumename}@${zfssnapshotname}) ..."    
        sudo zfs destroy "${ZFS_POOL}/${volumename}@${zfssnapshotname}"
        zcat $BACKUP_DIR/$volumesnapshot | sudo zfs receive -Fv "${ZFS_POOL}/${volumename}@${zfssnapshotname}"
        # zcat $BACKUP_DIR/$volumesnapshot | zfs receive -Fv "${ZFS_POOL}/${volumename}@${zfssnapshotname}"
      else
        echo "WARNING: No backup-file $backupfile found for ${ZFS_POOL}/${volumename}@${zfssnapshotname}!"    
      fi
    done
}

function zfs_clean_snaphsots() {
  namespace=$1
  kubectl -n $namespace delete volumesnapshot.snapshot --all
}