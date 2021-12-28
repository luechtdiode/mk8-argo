source ./scripts/file-incremental-backup-restore.sh

function pvc_backup()
{
  echo "backup for namespace $1, disable argo-autosync ..."
  kubectl patch application $1 -n argocd --type merge --patch "$(cat scripts/disable-sync-patch.yaml)"

  deployments=$(kubectl get deployments -n $1 -o jsonpath='{ .items[*].metadata.name }')
  for deployment in $deployments
  do
    echo "backup for namespace $1, stopping deployment $deployment ..."
    kubectl scale --replicas=0 --timeout=3m deployment/$deployment -n $1
  done;

  pvcnames=$(kubectl get persistentvolumeclaims -n $1 -o=jsonpath='{ .items[*]..name }')
  for pvcname in $pvcnames
  do
    volumename=$(kubectl get persistentvolumeclaims $pvcname -n $1 -o=jsonpath='{ ..volumeName }')
    storageClass=$(kubectl -n $1 get PersistentVolume $volumename -o jsonpath='{.spec.storageClassName}')

    case $storageClass in 
      microk8s-hostpath)
        SOURCE=$(kubectl -n $1 get PersistentVolume $volumename -o jsonpath='{.spec.hostPath.path}')
        BACKUP_DIR="$(pwd)/volumes-backup/$1/$pvcname"
        echo "--------------------------------"
        echo "backup for namespace $1, pvc-name: $pvcname, volume: $volumename from: $SOURCE ..."
        files_backup $SOURCE $BACKUP_DIR
        ;;
      openebs-hostpath)
        SOURCE="$PVCROOT/$volumename"
        BACKUP_DIR="$(pwd)/volumes-backup/$1/$pvcname"
        echo "--------------------------------"
        echo "backup for namespace $1, pvc-name: $pvcname, volume: $volumename from: $SOURCE ..."
        files_backup $SOURCE $BACKUP_DIR
        ;;
      *)
        echo "Sorry, this pvc is note Filesystem-based: $pvcname"
    esac
    echo "backup finished. Path $BACKUP_DIR"
  done;

  echo "--------------------------------"
  kubectl patch application $1 -n argocd --type merge --patch "$(cat scripts/enable-sync-patch.yaml)"
  echo "================================"
}

function pvc_restore()
{
  echo "restore for namespace $1, disable argo-autosync ..."
  kubectl patch application $1 -n argocd --type merge --patch "$(cat scripts/disable-sync-patch.yaml)"

  deployments=$(kubectl get deployments -n $1 -o jsonpath='{ .items[*].metadata.name }')
  for deployment in $deployments
  do
    echo "restore for namespace $1, stopping deployment $deployment ..."
    kubectl scale --replicas=0 --timeout=3m deployment/$deployment -n $1
  done;

  pvcnames=$(kubectl get persistentvolumeclaims -n $1 -o=jsonpath='{ .items[*]..name }')
  for pvcname in $pvcnames
  do
    BACKUP_DIR="$(pwd)/volumes-backup/$1/$pvcname"
    volumename=$(kubectl get persistentvolumeclaims $pvcname -n $1 -o=jsonpath='{ ..volumeName }')
    storageClass=$(kubectl -n $1 get PersistentVolume $volumename -o jsonpath='{.spec.storageClassName}')

    case $storageClass in
      microk8s-hostpath)
        TARGET_DIR=$(kubectl -n $1 get PersistentVolume $volumename -o jsonpath='{.spec.hostPath.path}')
        echo "--------------------------------"
        echo "restore for namespace $1, pvc-name: $pvcname, volume: $volumename to: $TARGET_DIR ..."
        files_restore $TARGET_DIR $BACKUP_DIR
        ;;
      openebs-hostpath)
        TARGET_DIR="$PVCROOT/$volumename"
        echo "--------------------------------"
        echo "restore for namespace $1, pvc-name: $pvcname, volume: $volumename to: $TARGET_DIR ..."
        files_restore $TARGET_DIR $BACKUP_DIR
        ;;
      *)
        echo "Sorry, this pvc is note Filesystem-based: $pvcname"
        echo $storageClass
    esac
    echo "restore finished. Path $BACKUP_DIR"
  done;

  echo "--------------------------------"
  kubectl patch application $1 -n argocd --type merge --patch "$(cat scripts/enable-sync-patch.yaml)"
  echo "================================"
}
