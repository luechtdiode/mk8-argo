source ./scripts/file-incremental-backup-restore.sh

function pvc_backup()
{
  namespace=$1
  deployments=$(kubectl get deployments -n $namespace -o jsonpath='{ .items[*].metadata.name }')
  if [ -z deployments ] 
  then
    echo "no active deployments in namespace $namespace found. No pvc backp applied!"
    return 1
  fi
  echo "backup for namespace $namespace, disable argo-autosync ..."
  kubectl patch application bootstrap -n argocd --type merge --patch "$(cat scripts/disable-sync-patch.yaml)"
  kubectl patch application $namespace -n argocd --type merge --patch "$(cat scripts/disable-sync-patch.yaml)"

  for deployment in $deployments
  do
    echo "backup for namespace $namespace, stopping deployment $deployment ..."
    kubectl scale --replicas=0 --timeout=3m deployment/$deployment -n $namespace
  done;

  pvcnames=${2:-$(kubectl get persistentvolumeclaims -n $namespace -o=jsonpath='{ .items[*]..name }')}
  for pvcname in $pvcnames
  do
    if [ $pfcfilter == "all" -o $pvcname == $pvcfilter]
    then
      volumename=$(kubectl get persistentvolumeclaims $pvcname -n $namespace -o=jsonpath='{ ..volumeName }')
      storageClass=$(kubectl -n $namespace get PersistentVolume $volumename -o jsonpath='{.spec.storageClassName}')

      case $storageClass in 
        microk8s-hostpath)
          SOURCE=$(kubectl -n $namespace get PersistentVolume $volumename -o jsonpath='{.spec.hostPath.path}')
          BACKUP_DIR="$(pwd)/volumes-backup/$namespace/$pvcname"
          echo "--------------------------------"
          echo "backup for namespace $namespace, pvc-name: $pvcname, volume: $volumename from: $SOURCE ..."
          files_backup $SOURCE $BACKUP_DIR
          ;;
        openebs-hostpath)
          SOURCE="$PVCROOT/$volumename"
          BACKUP_DIR="$(pwd)/volumes-backup/$namespace/$pvcname"
          echo "--------------------------------"
          echo "backup for namespace $namespace, pvc-name: $pvcname, volume: $volumename from: $SOURCE ..."
          files_backup $SOURCE $BACKUP_DIR
          ;;
        openebs-zfspv)
          SOURCE="$PVCROOT/$volumename"
          BACKUP_DIR="$(pwd)/volumes-backup/$namespace/$pvcname"
          echo "--------------------------------"
          echo "backup for namespace $namespace, pvc-name: $pvcname, volume: $volumename from: $SOURCE ..."
          zfs_backup $namespace $pvcname $BACKUP_DIR
          ;;
        *)
          echo "Sorry, this pvc is note Filesystem-based: $pvcname"
      esac
      echo "backup finished. Path $BACKUP_DIR"
    fi
  done;

  echo "--------------------------------"
  kubectl patch application $namespace -n argocd --type merge --patch "$(cat scripts/enable-sync-patch.yaml)"
  kubectl patch application bootstrap -n argocd --type merge --patch "$(cat scripts/enable-sync-patch.yaml)"
  echo "================================"
}

function pvc_restore()
{
  namespace=$1
  deployments=$(kubectl get deployments -n $namespace -o jsonpath='{ .items[*].metadata.name }')
  if [ -z deployments ] 
  then
    echo "no active deployments in namespace $namespace found. No pvc restore applied!"
    return 1
  fi

  for deployment in $deployments
  do
    until kubectl wait --for=condition=available --timeout=600s deployment/$deployment -n $namespace
    do
      echo "application $namespace not ready to connect deployment-pvcs. wait ..."
      sleep 5
    done
  done

  echo "restore for namespace $namespace, disable argo-autosync ..."
  kubectl patch application bootstrap -n argocd --type merge --patch "$(cat scripts/disable-sync-patch.yaml)"
  kubectl patch application $namespace -n argocd --type merge --patch "$(cat scripts/disable-sync-patch.yaml)"

  for deployment in $deployments
  do
    echo "restore for namespace $namespace, stopping deployment $deployment ..."
    kubectl scale --replicas=0 --timeout=3m deployment/$deployment -n $namespace
  done;

  pvcnames=${2:-$(kubectl get persistentvolumeclaims -n $namespace -o=jsonpath='{ .items[*]..name }')}
  for pvcname in $pvcnames
  do
    BACKUP_DIR="$(pwd)/volumes-backup/$namespace/$pvcname"
    volumename=$(kubectl get persistentvolumeclaims $pvcname -n $namespace -o=jsonpath='{ ..volumeName }')
    storageClass=$(kubectl -n $namespace get PersistentVolume $volumename -o jsonpath='{.spec.storageClassName}')

    case $storageClass in
      microk8s-hostpath)
        TARGET_DIR=$(kubectl -n $namespace get PersistentVolume $volumename -o jsonpath='{.spec.hostPath.path}')
        echo "--------------------------------"
        echo "restore for namespace $namespace, pvc-name: $pvcname, volume: $volumename to: $TARGET_DIR ..."
        files_restore $TARGET_DIR $BACKUP_DIR
        zfs_tar_migration $namespace $pvcname $BACKUP_DIR $TARGET_DIR
        ;;
      openebs-hostpath)
        TARGET_DIR="$PVCROOT/$volumename"
        echo "--------------------------------"
        echo "restore for namespace $namespace, pvc-name: $pvcname, volume: $volumename to: $TARGET_DIR ..."
        files_restore $TARGET_DIR $BACKUP_DIR
        zfs_tar_migration $namespace $pvcname $BACKUP_DIR $TARGET_DIR
        ;;
      openebs-zfspv)
        SOURCE="$PVCROOT/$volumename"
        echo "--------------------------------"
        echo "restore for namespace $namespace, pvc-name: $pvcname, volume: $volumename to: zfs-pool ..."
        zfs_restore $namespace $pvcname $BACKUP_DIR
        ;;
      *)
        echo "Sorry, this pvc is note Filesystem-based: $pvcname"
        echo $storageClass
    esac
    echo "restore finished. Path $BACKUP_DIR"
  done;

  echo "--------------------------------"
  kubectl patch application $namespace -n argocd --type merge --patch "$(cat scripts/enable-sync-patch.yaml)"
  kubectl patch application bootstrap -n argocd --type merge --patch "$(cat scripts/enable-sync-patch.yaml)"
  echo "================================"
}
