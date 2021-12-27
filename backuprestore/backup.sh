#!/bin/bash
cd "$(dirname "$0")"

# https://www.ionos.de/digitalguide/server/tools/backup-mit-tar-so-erstellen-sie-archive-unter-linux/

PVCROOT=/var/snap/microk8s/common/var/openebs/local
kubectl=$(which kubectl)

function volume_restore()
{
  BACKUP_DIR=$2
  TARGET=$1

  for d in ${TARGET}/*
  do
    echo "cleaning $d"
    sudo  rm -rf $d
  done

  echo "searching for .tar.bz2 archives to restore..."
  for archiv in ${BACKUP_DIR}/*.tar.bz2
  do
    sudo mkdir -p ${TARGET}/data
    sudo tar -xpjf $archiv -C ${TARGET}/data .
    echo "$archiv restored to ${TARGET}"
  done

  echo "searching for .tar.gz archives to restore..."
  for archiv in ${BACKUP_DIR}/backup-*.tar.gz
  do
    sudo tar -xpzf $archiv -C ${TARGET} .
    echo "$archiv restored to ${TARGET}"
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
        volume_restore $TARGET_DIR $BACKUP_DIR
        ;;
      openebs-hostpath)
        TARGET_DIR="$PVCROOT/$volumename"
        echo "--------------------------------"
        echo "restore for namespace $1, pvc-name: $pvcname, volume: $volumename to: $TARGET_DIR ..."
        volume_restore $TARGET_DIR $BACKUP_DIR
        ;;
      *)
        echo "Sorry, this pvc is note Filesystem-based: $pvcname"
        echo $storageClass
    esac
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
  DAY=$(date +%d)

  mkdir -p ${BACKUP_DIR}

  set -- ${BACKUP_DIR}/backup-??.tar.gz
  lastname=${!#}
  backupnr=${lastname##*backup-}
  backupnr=${backupnr%%.*}
  backupnr=${backupnr//\?/0}
  backupnr=$[10#${backupnr}]

  if [ "$[backupnr++]" -ge $DAY ]; then
    rm -rf ${ROTATE_DIR}_RETENTION
    mv ${ROTATE_DIR}/* ${ROTATE_DIR}_RETENTION
    mkdir -p ${ROTATE_DIR}/${DATE}
    mv ${BACKUP_DIR}/b* ${ROTATE_DIR}/${DATE}
    mv ${BACKUP_DIR}/t* ${ROTATE_DIR}/${DATE}
    mv ${BACKUP_DIR}/*.log ${ROTATE_DIR}/${DATE}
    backupnr=1
  fi

  backupnr=0${backupnr}
  backupnr=${backupnr: -2}
  filename=backup-${backupnr}.tar.gz
  logfilename=pvc-backup.log
  echo $DATE                                                                                    >> ${BACKUP_DIR}/$logfilename
  echo "taring from $SOURCE"                                                                    >> ${BACKUP_DIR}/$logfilename
  echo "         to ${BACKUP_DIR}/$filename"                                                    >> ${BACKUP_DIR}/$logfilename
  echo $(sudo tar -cpzf ${BACKUP_DIR}/${filename} -g ${BACKUP_DIR}/${TIMESTAMP} -C ${SOURCE} .) >> ${BACKUP_DIR}/$logfilename
  cat ${BACKUP_DIR}/$logfilename
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
        volume_backup $SOURCE $BACKUP_DIR
        ;;
      openebs-hostpath)
        SOURCE="$PVCROOT/$volumename"
        BACKUP_DIR="$(pwd)/volumes-backup/$1/$pvcname"
        echo "--------------------------------"
        echo "backup for namespace $1, pvc-name: $pvcname, volume: $volumename from: $SOURCE ..."
        volume_backup $SOURCE $BACKUP_DIR
        ;;
      *)
        echo "Sorry, this pvc is note Filesystem-based: $pvcname"
    esac
    echo "backup finished. Path $BACKUP_DIR"
  done;

  echo "--------------------------------"
  kubectl patch application $1 -n argocd --type merge --patch "$(cat enable-sync-patch.yaml)"
  echo "================================"
}

function install()
{
  croncmd="kubectl=$(which kubectl) && $(pwd)/backup.sh"
  sudo crontab -u root -l | grep -v 'backuprestore/backup.sh' > crontabcleaned.txt
  cp crontabcleaned.txt crontabupdated.txt
  echo "* * * * * $croncmd >> $(pwd)/backup.log 2>&1" >> crontabupdated.txt
  sudo crontab -u root crontabupdated.txt
  # sudo cp crontabupdated.txt /etc/crontab
}

function cloudsync()
{
  case $1 in
    down)
    ;;
    *)
      SOURCE="$(pwd)/volumes-backup"
      BACKUP_DIR="$(pwd)/cloud-backup"
      DB_DIR="$(pwd)/db-backup"
      echo "--------------------------------"
      echo "cloud-backup from: $SOURCE ..."
      volume_backup $SOURCE $BACKUP_DIR

      for file in $(find $BACKUP_DIR/* -name "backup*.tar.gz" | xargs ); do
        uplink cp $file sj://sharevic/manualbackup/$(echo $file | awk -F/ '{ print $NF }')
      done

      uplink cp secrets.tar.gz sj://sharevic/manualbackup/secrets.tar.gz

      for file in $(find $DB_DIR/* -name "*.dump" | xargs ); do
        uplink cp $file sj://sharevic/manualbackup/db/$(echo $file | awk -F/ '{ print $NF }')
      done
    ;;
  esac
}

function dbbackup()
{
  mkdir -p $(pwd)/db-backup
  NAMESPACE="$1"
  PG_USER="${2:-$NAMESPACE}"
  DB_NAME="${3:-$PG_USER}"
  DUMPFILE="db-backup/$NAMESPACE-$DB_NAME-database.dump"
  echo "taking backup from db $DB_NAME, user $PG_USER in $NAMESPACE to $DUMPFILE ..."
  postgrespod=$(kubectl -n $NAMESPACE get pod -l component=postgres -o jsonpath='{.items[*].metadata.name}')
  kubectl -n $NAMESPACE exec $postgrespod -- bash \
    -c "pg_dump -U $PG_USER --no-password --format=c --blobs --section=pre-data --section=data --section=post-data --encoding 'UTF8' $DB_NAME" \
    > $DUMPFILE
  echo "backup finished"
}

# dbrestore <namespace> <pg-user> <db-name>
function dbrestore()
{
  NAMESPACE="$1"
  PG_USER="${2:-$NAMESPACE}"
  DB_NAME="${3:-$PG_USER}"
  DUMPFILE="db-backup/$NAMESPACE-$DB_NAME-database.dump"
  echo "restoring backup from $DUMPFILE to db $DB_NAME, user $PG_USER in $NAMESPACE ..."
  postgrespod=$(kubectl -n $NAMESPACE get pod -l component=postgres -o jsonpath='{.items[*].metadata.name}')
  kubectl -n $NAMESPACE exec $postgrespod -- bash \
    -c "echo \"select pg_terminate_backend(pg_stat_activity.pid) from pg_stat_activity where pg_stat_activity.datname = '$DB_NAME' and pid <> pg_backend_pid();\" | psql -U kutuapp \
        && dropdb -U $PG_USER --if-exists $DB_NAME && createdb -U $PG_USER -T template0 $DB_NAME"
  cat $DUMPFILE | kubectl -n $NAMESPACE exec -i $postgrespod -- pg_restore -U $PG_USER --no-password --section=pre-data --section=data --section=post-data --clean --dbname $DB_NAME
  echo "restore finished"
}

# ns_restore <namespace> <database>
function ns_dbrestore()
{
  case $1 in
    kmgetubs19)
      dbrestore kmgetubs19 odoo ${2:-odoo}
    ;;
    kutuapp-test)
      dbrestore kutuapp-test kutuapp ${2:-kutuapp}
    ;;
    kutuapp)
      dbrestore kutuapp kutuapp ${2:-kutuapp}
    ;;
  esac
}

function secretbackup()
{
  # find from mk8-argo project-root
  find ../* -name "*-secret.yaml" | xargs tar -czf secrets.tar.gz
  echo "secrets collected and saved to secrets.tar.gz"
}

function secretrestore()
{
  tar -zxvf secrets.tar.gz -C .. # extract contents of secrets.tar.gz
  for file in $(tar -ztvf secrets.tar.gz  | awk -F' ' '{ if($NF != "") print $NF }' | xargs ); do
    if [ -e "../$file" ]; then
      newname=$(echo "../$file" | sed 's/-secret/-sealedsecret/')
      namespace=$(echo $newname | cut -d/ -f2 )
      kubeseal <"../$file" -o yaml >$newname -n $namespace
      echo "Secret $file restored and resealed as $newname in namespace $namespace"
    fi
  done
}

function migrate()
{
  # migrate <namespace> <plutobackup> <pvcname> => fe. migrate kutuapp backup-kutu-db-data.tar.bz2 kutu-data
  TARGET_DIR=volumes-backup/$1/$3
  mkdir -p $TARGET_DIR
  cp ~/pluto-roland/docker-apps/$2 $TARGET_DIR
}

if [ -z "$1" ]
then
  dbbackup kutuapp kutuapp kutuapp
  dbbackup kutuapp-test kutuapp kutuapp
  dbbackup kmgetubs19 odoo
  ns_backup kmgetubs19
  ns_backup keycloak
  ns_backup kutuapp-test
  ns_backup kutuapp
  ns_backup sharevic
  ns_backup pg-admin
  secretbackup
else
  case $1 in
    cloudsync)
      cloudsync $2
      ;;
    secrets)
      secretbackup
      ;;
    dbbackup)
      dbbackup kutuapp kutuapp kutuapp
      dbbackup kutuapp-test kutuapp kutuapp
      dbbackup kmgetubs19 odoo
      ;;
    dbrestore)
      ns_dbrestore $2 $3
      ;;
    restore)
      ns_restore $2
      ;;
    backup)
      ns_backup $2
      ;;
    secretrestore)
      secretrestore
      ;;
    migrate)
      migrate $2 $3 $4
      ;;
    install)
      install
      echo "daily backup in crontab registered for backup-location $(pwd)"
      ;;
    *)
      echo "Sorry, I don't understand"
      echo 'Usage:
         ./backup.sh (zero-args) => make incremental backup per month from all volumes of the registered namespaces
         backup <namespace>      => make incremental backup per month from all volumes of the specified namespace
         dbbackup                => make zero-downtime db-backup or registered databases
         secrets                 => collects all *secret.yaml from the sibling-folders (namespaces)
         restore <namespace>     => restore the backed up volumes of the specified namespace
         dbrestore <namespace>   => restore the database from its last stored backup
         dbrestore <namespace> <dbname> => restore database to a dedicated database
         secretrestore           => extracts secrets from backup and reseals the sealedsecrets
         cloudsync               => save all backups to storj bucket
         migrate <namespace> <plutobackup> <pvcname> => fe. 
           migrate kutuapp kutu-db-data-backup.tar.bz2 kutu-data
           migrate kutuapp kutuapp-backup.tar.bz2 kutuapp-data
           migrate kutuapp-test kutu-test-db-data-backup.tar.bz2 kutu-data
           migrate kutuapp-test kutuapp-test-backup.tar.bz2 kutuapp-data
      '
      ;;
  esac
fi

