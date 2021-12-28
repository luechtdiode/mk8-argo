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

# cloudsync [up | down] defaults to up
function cloudsync()
{
  case $1 in
    down)
    ;;
    *)
      uplink cp secrets.tar.gz sj://sharevic/manualbackup/secrets.tar.gz

      CLUSTER_DIR="$(pwd)/cluster-backup"
      for file in $(find $CLUSTER_DIR/* -name "*.tar.gz" | xargs ); do
        uplink cp $file sj://sharevic/manualbackup/cluster/$(echo $file | awk -F/ '{ print $NF }')
      done

      DB_DIR="$(pwd)/db-backup"
      for file in $(find $DB_DIR/* -name "*.dump" | xargs ); do
        uplink cp $file sj://sharevic/manualbackup/db/$(echo $file | awk -F/ '{ print $NF }')
      done

      # collect all pvc incremental backups to one cloud-pvc incremental backup
      SOURCE="$(pwd)/volumes-backup"
      BACKUP_DIR="$(pwd)/cloud-backup"
      echo "--------------------------------"
      echo "cloud-backup from: $SOURCE ..."
      volume_backup $SOURCE $BACKUP_DIR

      for file in $(find $BACKUP_DIR/* -name "backup*.tar.gz" | xargs ); do
        uplink cp $file sj://sharevic/manualbackup/volumes/$(echo $file | awk -F/ '{ print $NF }')
      done
    ;;
  esac
}

# findPostgresPod <namespace>
function findPostgresPod()
{
  NAMESPACE="$1"
  postgrespod=$(kubectl -n $NAMESPACE get pod -l component=postgres -o jsonpath='{.items[*].metadata.name}')
  [ -z $postgrespod ] && postgrespod=$(kubectl -n $NAMESPACE get pod -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep postgres)
  echo $postgrespod  
}

# dbbackup <namespace> [<pg-user> [<db-name>]]
function dbbackup()
{
  mkdir -p $(pwd)/db-backup
  NAMESPACE="$1"
  PG_USER="${2:-$NAMESPACE}"
  DB_NAME="${3:-$PG_USER}"
  DUMPFILE="db-backup/$NAMESPACE-$DB_NAME-database.dump"
  echo "taking backup from db $DB_NAME, user $PG_USER in $NAMESPACE to $DUMPFILE ..."
  postgrespod=$(findPostgresPod $NAMESPACE)
  kubectl -n $NAMESPACE exec $postgrespod -- bash \
    -c "pg_dump -U $PG_USER --no-password --format=c --blobs --section=pre-data --section=data --section=post-data --encoding 'UTF8' $DB_NAME" \
    > $DUMPFILE
  echo "backup finished"
}

# dbrestore <namespace> [<pg-user> [<db-name>]]
function dbrestore()
{
  NAMESPACE="$1"
  PG_USER="${2:-$NAMESPACE}"
  DB_NAME="${3:-$PG_USER}"
  DUMPFILE="db-backup/$NAMESPACE-$DB_NAME-database.dump"
  echo "restoring backup from $DUMPFILE to db $DB_NAME, user $PG_USER in $NAMESPACE ..."
  postgrespod=$(findPostgresPod $NAMESPACE)
  kubectl -n $NAMESPACE exec $postgrespod -- bash \
    -c "echo \"select pg_terminate_backend(pg_stat_activity.pid) from pg_stat_activity where pg_stat_activity.datname = '$DB_NAME' and pid <> pg_backend_pid();\" | psql -U $PG_USER \
        && dropdb -U $PG_USER --if-exists $DB_NAME && createdb -U $PG_USER -T template0 $DB_NAME"
  cat $DUMPFILE | kubectl -n $NAMESPACE exec -i $postgrespod -- pg_restore -U $PG_USER --no-password --section=pre-data --section=data --section=post-data --clean --dbname $DB_NAME
  echo "restore finished"
}

# ns_restore <namespace> [<target-databasename>]
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
    keycloak)
      dbrestore keycloak keycloak ${2:-keycloak}
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

function clusterbackup()
{
  mkdir -p ./cluster-backup
  sudo microk8s stop
  tar -c -v -z --exclude=*.yaml --exclude=metadata* -f ./cluster-backup/dqlite-data.tar.gz /var/snap/microk8s/current/var/kubernetes/backend
  sudo microk8s start
}

function clusterretore()
{
  DQLITE_BACKUP=$(pwd)/cluster-backup/dqlite-data.tar.gz
  cd /.
  su $whoami
    microk8s stop
    tar zxfv DQLITE_BACKUP
    microk8s start
  exit
  cd -
}

function usage() {
  echo 'Usage:
    ./backup.sh (zero-args) => make cluster-, secret-, db- and incremental pvc-backup per month from all volumes of the registered namespaces
    backup <namespace>      => make incremental pvc-backup per month from all volumes of the specified namespace
    dbbackup                => make zero-downtime db-backup or registered databases
    secrets                 => collects all *secret.yaml from the sibling-folders (namespaces)
    cluster                 => make backup of cluster resources (kubernetes dqlite-data)
    restore <namespace>     => restore the backed up volumes of the specified namespace
    dbrestore <namespace>   => restore the database from its last stored backup
    dbrestore <namespace> <dbname> => restore database to a dedicated database
    secretrestore           => extracts secrets from backup and reseals the sealedsecrets
    cloudsync               => save all current backups to storj bucket
    cloudsync up            => save all current backups to storj bucket
    cloudsync down          => download all backups from storj bucket
    help                    => print usage
  '
}

if [ -z "$1" ]
then
  secretbackup
  dbbackup kutuapp kutuapp kutuapp
  dbbackup kutuapp-test kutuapp kutuapp
  dbbackup kmgetubs19 odoo
  dbbackup keycloak keycloak keycloak
  ns_backup kmgetubs19
  ns_backup keycloak
  ns_backup kutuapp-test
  ns_backup kutuapp
  ns_backup sharevic
  ns_backup pg-admin
  clusterbackup
else
  case $1 in
    cloudsync)
      cloudsync $2
      ;;
    cluster)
      clusterbackup
      ;;      
    secrets)
      secretbackup
      ;;
    dbbackup)
      dbbackup kutuapp kutuapp kutuapp
      dbbackup kutuapp-test kutuapp kutuapp
      dbbackup kmgetubs19 odoo
      dbbackup keycloak keycloak keycloak
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
    clusterrestore)
      clusterrestore
      ;;
    install)
      install
      echo "daily backup in crontab registered for backup-location $(pwd)"
      ;;
    help)
      usage
      ;;
    *)
      echo "Sorry, I don't understand"
      usage
      ;;
  esac
fi

