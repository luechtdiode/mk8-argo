#!/bin/bash

# https://www.ionos.de/digitalguide/server/tools/backup-mit-tar-so-erstellen-sie-archive-unter-linux/

PVCROOT=/var/snap/microk8s/common/var/openebs/local

function volume_restore()
{
  BACKUP_DIR=$2
  TARGET=$1

  for archiv in ${BACKUP_DIR}/backup-*.tar.gz
  do
    tar -xpzf $archiv -C ${TARGET}
  done
}

function ns_restore()
{
  echo "restore for namespace $1, disable argo-autosync ..."
  kubectl patch application $1 -n argocd --type merge --patch "$(cat disable-sync-patch.yaml)"

  deployments=$(kubectl get deployments -n $1 -o jsonpath='{ .items[*].metadata.name }')
  for deployment in $deployments
  do
    echo "restore for namespace $1, stopping deployment $deployment ..."
    kubectl scale --replicas=0 --timeout=3m deployment/$deployment -n $1
  done;

  volumes=$(kubectl get persistentvolumeclaims -n $1 -o=jsonpath='{ .items[*].spec.volumeName }')
  for volume in $volumes
  do
    echo "--------------------------------"
    echo "restore for namespace $1, volume: $volume ..."
    BACKUP_DIR="$(pwd)/volumes-backup/$1/$volume"
    SOURCE="$PVCROOT/$volume"
    volume_restore $SOURCE $BACKUP_DIR
    echo "restore finished. Path $BACKUP_DIR"
  done;

  echo "--------------------------------"
  kubectl patch application $1 -n argocd --type merge --patch "$(cat enable-sync-patch.yaml)"
  echo "================================"
}

function volume_backup()
{
  BACKUP_DIR=$2
  ROTATE_DIR="$2/rotate"
  TIMESTAMP="timestamp.dat"
  SOURCE=$1
  DATE=$(date +%Y-%m-%d-%H%M%S)

  mkdir -p ${BACKUP_DIR}

  set -- ${BACKUP_DIR}/backup-??.tar.gz
  lastname=${!#}
  backupnr=${lastname##*backup-}
  backupnr=${backupnr%%.*}
  backupnr=${backupnr//\?/0}
  backupnr=$[10#${backupnr}]

  if [ "$[backupnr++]" -ge 30 ]; then
    rm -rf ${ROTATE_DIR}_RETENTION
    mv ${ROTATE_DIR}/* ${ROTATE_DIR}_RETENTION  
    mkdir -p ${ROTATE_DIR}/${DATE}
    mv ${BACKUP_DIR}/b* ${ROTATE_DIR}/${DATE}
    mv ${BACKUP_DIR}/t* ${ROTATE_DIR}/${DATE}
    backupnr=1
  fi

  backupnr=0${backupnr}
  backupnr=${backupnr: -2}
  filename=backup-${backupnr}.tar.gz
  sudo tar -cpzfW ${BACKUP_DIR}/${filename} -g ${BACKUP_DIR}/${TIMESTAMP} ${SOURCE}
}

function ns_backup()
{
  echo "backup for namespace $1, disable argo-autosync ..."
  kubectl patch application $1 -n argocd --type merge --patch "$(cat disable-sync-patch.yaml)"

  deployments=$(kubectl get deployments -n $1 -o jsonpath='{ .items[*].metadata.name }')
  for deployment in $deployments
  do
    echo "backup for namespace $1, stopping deployment $deployment ..."
    kubectl scale --replicas=0 --timeout=3m deployment/$deployment -n $1
  done;

  volumes=$(kubectl get persistentvolumeclaims -n $1 -o=jsonpath='{ .items[*].spec.volumeName }')
  for volume in $volumes
  do
    echo "--------------------------------"
    echo "backup for namespace $1, volume: $volume ..."
    BACKUP_DIR="$(pwd)/volumes-backup/$1/$volume"
    SOURCE="$PVCROOT/$volume"
    volume_backup $SOURCE $BACKUP_DIR
    echo "backup finished. Path $BACKUP_DIR"
  done;

  echo "--------------------------------"
  kubectl patch application $1 -n argocd --type merge --patch "$(cat enable-sync-patch.yaml)"
  echo "================================"
}

if [ -z "$1" ]
then
  ns_backup kmgetubs19
  ns_backup keycloak
  ns_backup kutuapp-test
  ns_backup sharevic
else
  case $1 in
	restore)
		ns_restore $2
    break
		;;
	backup)
		ns_backup $2
		break
		;;
	*)
		echo "Sorry, I don't understand"
		;;
  esac
fi
