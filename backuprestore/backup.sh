#!/bin/bash

PVCROOT=/var/snap/microk8s/common/var/openebs/local

function volume_backup()
{
  BACKUP_DIR=$2
  ROTATE_DIR="$2/rotate"
  TIMESTAMP="timestamp.dat"
  SOURCE=$1
  DATE=$(date +%Y-%m-%d-%H%M%S)

  # EXCLUDE="--exclude=/mnt/* --exclude=/proc/* --exclude=/sys/* --exclude=/tmp/*"

  mkdir -p ${BACKUP_DIR}

  set -- ${BACKUP_DIR}/backup-??.tar.gz
  lastname=${!#}
  backupnr=${lastname##*backup-}
  backupnr=${backupnr%%.*}
  backupnr=${backupnr//\?/0}
  backupnr=$[10#${backupnr}]

  if [ "$[backupnr++]" -ge 30 ]; then
    mkdir -p ${ROTATE_DIR}/${DATE}
    mv ${BACKUP_DIR}/b* ${ROTATE_DIR}/${DATE}
    mv ${BACKUP_DIR}/t* ${ROTATE_DIR}/${DATE}
    backupnr=1
  fi

  backupnr=0${backupnr}
  backupnr=${backupnr: -2}
  filename=backup-${backupnr}.tar.gz
  sudo tar -cpzf ${BACKUP_DIR}/${filename} -g ${BACKUP_DIR}/${TIMESTAMP} ${SOURCE} #-X $EXCLUDE ${SOURCE}
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
    echo "backup for namespace $1, volume: $volume ..."
    BACKUP_DIR="$(pwd)/volumes-backup/$1/$volume"
    SOURCE="$PVCROOT/$volume"
    volume_backup $SOURCE $BACKUP_DIR
    echo "backup finished. Path $BACKUP_DIR"
    echo "================================"
  done;

  kubectl patch application $1 -n argocd --type merge --patch "$(cat enable-sync-patch.yaml)"
}


ns_backup kmgetubs19
ns_backup keycloak
ns_backup kutuapp-test
ns_backup sharevic
