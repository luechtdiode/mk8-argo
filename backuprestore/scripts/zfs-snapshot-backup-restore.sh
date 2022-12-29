#!/bin/bash

# https://docs.oracle.com/cd/E23824_01/html/821-1448/recover-1.html#scrolltoc

ZFS_POOL=zfspv-pool
source ./scripts/file-incremental-backup-restore.sh

# zfs_backup $namespace $pvcname $BACKUP_DIR
function zfs_backup() {
  namespace=$1
  pvc=$2
  TARGET=$3
  
  mkdir -p ${TARGET}
  zfs_clean_snapshot_archives $namespace
  
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

  existingsnapshots=($(kubectl -n $namespace get volumesnapshot.snapshot -o jsonpath="{.items[?(@.spec.source.persistentVolumeClaimName=='$pvc')].metadata.name}"))
  volumesnapshots=(  $(kubectl -n $namespace get volumesnapshot.snapshot -o jsonpath="{.items[?(@.spec.source.persistentVolumeClaimName=='$pvc')].status.boundVolumeSnapshotContentName}"))

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

# zfs_tar_migration $namespace $pvcname $BACKUP_DIR $TARGET_DIR
function zfs_tar_migration() {
  namespace=$1
  pvcname=$2
  BACKUP_DIR=$3
  TEMP_DIR=$(pwd)/zfstemp
  TARGET_DIR=$4
  files=$(find ${BACKUP_DIR}/*.gz | grep -vF .tar.)
  if ! [ -z $files ]
  then
    echo "--------------------------------"
    echo "migrate zfs-tar for namespace $namespace, pvcname: $pvcname via: $TARGET_DIR ..."

    sudo zfs create -o mountpoint=$TEMP_DIR "${ZFS_POOL}/${pvcname}"
    if zfs_restore $namespace $pvcname $BACKUP_DIR
    then
      for d in ${TARGET_DIR}/*
      do
        echo "cleaning $d"
        sudo  rm -rf $d
      done
    fi
    sudo mv $TEMP_DIR $TARGET_DIR

    sudo zfs unmount $TEMP_DIR
    sudo zfs set mountpoint=none "${ZFS_POOL}/${pvcname}"
    sudo zfs destroy -f "${ZFS_POOL}/${pvcname}"
    rm -rf $TEMP_DIR
  else
    echo "--------------------------------"
    echo "no migration zfs->tar for namespace $namespace, pvcname: $pvcname files: $files ..."
  fi
}

# tar_zfs_migration $namespace $volumename $BACKUP_DIR
function tar_zfs_migration() {
  namespace=$1
  volumename=$2
  BACKUP_DIR=$3
  TARGET_DIR=$(pwd)/zfstemp
  files=$(find ${BACKUP_DIR}/*.tar.gz)
  if ! [ -z $files ]
  then
    echo "--------------------------------"
    echo "migrate tar->zfs for namespace $namespace, volume: $volumename via: $TARGET_DIR ..."

    sudo zfs set mountpoint=$TARGET_DIR "${ZFS_POOL}/${volumename}"
    files_restore $TARGET_DIR $BACKUP_DIR
    sudo zfs unmount $TARGET_DIR
    sudo zfs set mountpoint=none "${ZFS_POOL}/${volumename}"
  else
    echo "--------------------------------"
    echo "no migration tar->zfs for namespace $namespace, volume: $volumename files: $files ..."
  fi
}

# zfs_restore $namespace $pvcname $BACKUP_DIR
function zfs_restore() {
  namespace=$1
  pvc=$2 #kubectl -n $namespace get volumesnapshot.snapshot -o jsonpath='{.items[*].spec.source.persistentVolumeClaimName}'
  BACKUP_DIR=$3
  volumename=$(kubectl get persistentvolumeclaims $pvc -n $namespace -o=jsonpath='{ ..volumeName }')
  echo "restoring $volumename from archived snapshots in $BACKUP_DIR:"

  zfs_clean_snapshots $namespace

  number=1
  echo "searching for .gz archives to restore..."
  files=$(find ${BACKUP_DIR}/*.gz | grep -vF .tar.)
  for backupfile in files
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

  # no gz-files to restore, then try migration from tar to zfs ...
  [ number -eq 1 ] tar_zfs_migration $namespace $volumename $BACKUP_DIR
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
  for backupfile in ${BACKUP_DIR}/*.gz
  do
    sudo rm $backupfile
  done
}

function zfs_clean_snapshots() {
  namespace=$1
  kubectl -n $namespace delete volumesnapshot.snapshot --all
  sleep 5
  othersnaps="$(zfs list -H -o name -t snapshot)"
  if [ ! -z "$othersnaps" ]
  then
   echo "deleting other snapshots: $othersnaps"
   zfs list -H -o name -t snapshot | grep "${ZFS_POOL}/${volumename}" | xargs -n1 sudo zfs destroy
  fi
}
