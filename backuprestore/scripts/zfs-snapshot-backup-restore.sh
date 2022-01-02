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

  existingsnapshots=($(kubectl -n $namespace get volumesnapshot.snapshot -o jsonpath='{.items[*].metadata.name}'))
  number=$(echo $(expr "${#existingsnapshots[@]}" + 1))
  echo "  next snapshot-number should be $number"

  snap=($(sed -e "s/pvcname/$pvc/g" -e "s/zfspv-snapname/snap-$number/g" scripts/zfs-snapshot.yaml | kubectl -n $namespace apply -f -)[0])
  echo "  Snapshot creation submitted: $snap"

  # kubectl -n $namespace $snap wait --for=condition=jsonpath="{.status.readyToUse}"
  ready=$(kubectl -n $namespace get $snap -o jsonpath="{.status.readyToUse}")
  
  while [ $ready != "true" ]
  do
    echo "  snapshot not ready yet, wait another 1 seconds ..."
    sleep 1
    ready=$(kubectl -n $namespace get $snap -o jsonpath="{.status.readyToUse}")
  done
  echo "  Snapshot is ready: $ready"

  volumesnapshots=($(kubectl -n $namespace get volumesnapshot.snapshot -o jsonpath="{.items[?(@.spec.source.persistentVolumeClaimName=='$pvc')].status.boundVolumeSnapshotContentName}"))

  lastsnap=""
  lastsnapname=""
  for i in "${!volumesnapshots[@]}"
  do
    volumesnapshot="${volumesnapshots[$i]}"
    snapname="${existingsnapshots[$i]}"
    backupfile=$TARGET/${volumesnapshot}.gz
    zfssnapshotname=$(echo $volumesnapshot | sed "s/snapcontent-/snapshot-/g")
    snapshotfullname="${ZFS_POOL}/${volumename}@${zfssnapshotname}"
    if [ ! -f "$backupfile" ]; then
      if [ -z $lastsnap ]; then
        echo "  taking zfs backup of snapshot $snapname"
        echo "     pvc $pvc / volumesnapshot $volumesnapshot"
        echo "    from $snapshotfullname"
        echo "      to $backupfile ..."
        sudo zfs send -cv $snapshotfullname | gzip > $backupfile
      else
        echo "  taking incremental zfs backup of snapshot $lastsnapname - $snapname"
        echo "     pvc $pvc / volumesnapshot $volumesnapshot"
        echo "    from $snapshotfullname"
        echo "     via $lastsnap"
        echo "      to $backupfile ..."
        sudo zfs send -i $lastsnap $snapshotfullname | gzip > $backupfile
      fi
    else 
        echo "  zfs backup of snapshot $snapname already exists"
        echo "     pvc $pvc / volumesnapshot $volumesnapshot"
        echo "     for $volumesnapshot/$zfssnapshotname (${ZFS_POOL}/${volumename}@${zfssnapshotname})..."
    fi
    lastsnap=$snapshotfullname
    lastsnapname=$snapname
  done
}

# zfs_restore $namespace $pvcname $BACKUP_DIR
function zfs_restore() {
  namespace=$1
  pvc=$2 #kubectl -n $namespace get volumesnapshot.snapshot -o jsonpath='{.items[*].spec.source.persistentVolumeClaimName}'
  BACKUP_DIR=$3
  volumename=$(kubectl get persistentvolumeclaims $pvc -n $namespace -o=jsonpath='{ ..volumeName }')
  echo "restoring $volumename from archived snapshots in $BACKUP_DIR:"

  zfs_clean_snaphsots $namespace

  number=1
  echo "searching for .gz archives to restore..."
  for backupfile in ${BACKUP_DIR}/*.gz
  do
    zfssnapshotname=$(echo $backupfile | sed "s/snapcontent-/snapshot-/g" | awk -F/ '{ if($NF != "") print $NF }' | sed "s/.gz//g")
    echo "restoring zfs backup #$number"
    echo "  for $pvc"
    echo " from $backupfile"
    echo "   to (${ZFS_POOL}/${volumename}@${zfssnapshotname}) ..."            
    zcat $backupfile | sudo zfs receive -Fv "${ZFS_POOL}/${volumename}" # @${zfssnapshotname}
    snap=($(sed -e "s/pvcname/$pvc/g" -e "s/zfspv-snapname/snap-$number/g" scripts/zfs-snapshot.yaml | kubectl -n $namespace apply -f -)[0])
    let "number=number+1"
  done
}

# zfs_restore $namespace $pvcname $BACKUP_DIR
function zfs_restore_from_zfssnapshotvolume() {
    namespace=$1
    pvc=$2 #kubectl -n $namespace get volumesnapshot.snapshot -o jsonpath='{.items[*].spec.source.persistentVolumeClaimName}'
    BACKUP_DIR=$3
    volumename=$(kubectl get persistentvolumeclaims $pvc -n $namespace -o=jsonpath='{ ..volumeName }')
    volumesnapshots=($(kubectl -n $namespace get volumesnapshot.snapshot -o jsonpath='{.items[*].status.boundVolumeSnapshotContentName}'))
    echo "restoring $volumename with ${#volumesnapshots[@]} snapshots:"
    for i in "${!volumesnapshots[@]}"
    do
      volumesnapshot="${volumesnapshots[$i]}"
      backupfile=$BACKUP_DIR/${volumesnapshot}.gz
      if [ -f "$backupfile" ]; then
        snapname=$(kubectl -n $namespace get volumesnapshot.snapshot -o jsonpath="{.items[$i].metadata.name}")
        zfssnapshotname=$(echo $volumesnapshot | sed "s/snapcontent-/snapshot-/g")
        echo "  - $snapname:"
        echo "    from ${volumesnapshot}.gz"
        echo "      to $zfssnapshotname"
        sudo zfs destroy -r "${ZFS_POOL}/${volumename}@$zfssnapshotname"
      fi
    done

    for i in "${!volumesnapshots[@]}"
    do
      volumesnapshot="${volumesnapshots[$i]}"
      backupfile=$BACKUP_DIR/${volumesnapshot}.gz
      if [ -f "$backupfile" ]; then
        zfssnapshotname=$(echo $volumesnapshot | sed "s/snapcontent-/snapshot-/g")
        echo "restoring zfs backup"
        echo "  for $pvc/$volumesnapshot"
        echo " from $backupfile"
        echo "   to (${ZFS_POOL}/${volumename}@${zfssnapshotname}) ..."            
        zcat $BACKUP_DIR/$volumesnapshot | sudo zfs receive -Fv "${ZFS_POOL}/${volumename}@${zfssnapshotname}"
        # zcat $BACKUP_DIR/$volumesnapshot | zfs receive -Fv "${ZFS_POOL}/${volumename}@${zfssnapshotname}"
      else
        echo "WARNING: No backup-file $backupfile found"
        echo "         for ${ZFS_POOL}/${volumename}@${zfssnapshotname}!"    
      fi
    done
}

function zfs_clean_snapshot_archives() {
  namespace=$1
  BACKUP_DIR="$(pwd)/volumes-backup/$namespace/$pvcname"
  # sudo find 
  
}

function zfs_clean_snapshots() {
  namespace=$1
  kubectl -n $namespace delete volumesnapshot.snapshot --all
  sleep 5
  othersnaps="$(zfs list -H -o name -t snapshot)"
  if [ ! -z $othersnaps ]
  then
   echo "deleting other snapshots: $othersnaps"
   zfs list -H -o name -t snapshot | grep "${ZFS_POOL}/${volumename}" | xargs -n1 sudo zfs destroy
  fi
}
