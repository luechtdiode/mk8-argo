#!/bin/bash
cd "$(dirname "$0")"

PVCROOT=/var/snap/microk8s/common/var/openebs/local
kubectl=$(which kubectl)
uplink=$(which uplink)

echo "kubectl found at $kubectl"
echo "uplink found at $uplink"
echo "current path: $PATH"
echo "current user: $(whoami)"

source ./scripts/secret-backup-restore.sh
source ./scripts/db-backup-restore.sh
source ./scripts/file-incremental-backup-restore.sh
source ./scripts/pvc-backup-restore.sh
source ./scripts/zfs-snapshot-backup-restore.sh
source ./scripts/cluster-backup-restore.sh
source ./scripts/cloudsync.sh
source ./scripts/install.sh

function usage() {
  echo 'Usage:
    ./main.sh <args>; where args:
    all                     => make cluster-, secret-, db- and incremental pvc-backup per month from all volumes of the registered namespaces
    short                   => make backup of secrets and db of the registered namespaces and push new bucked with cloudsync up
    backup <namespace>      => make incremental pvc-backup per month from all volumes of the specified namespace
    dbbackup                => make zero-downtime db-backup or registered databases
    secrets                 => collects all *secret.yaml from the sibling-folders (namespaces)
    cluster                 => make backup of cluster resources (kubernetes dqlite-data)
    restore <namespace>     => restore the backed up volumes of the specified namespace
    dbrestore <namespace>   => restore the database from its last stored backup
    dbrestore <namespace> <dbname> => restore database to a dedicated database
    secretrestore           => extracts secrets from backup and reseals the sealedsecrets
    privatesecretrestore    => extracts private secrets from backup and applies in the namespaces
    clusterrestore          => restores cluster resouces (kubernetes dqlite-data)
    cloudsync               => save all current backups to storj bucket
                               [[up | down] bucket-qualifier] defaults to up today 
    cloudsync up            => save all current backups to storj bucket
    cloudsync down          => download all backups from storj bucket
    clean_snapshots <namespace> => clean zfs-snapshots
    help                    => print usage
  '
}

# ns_restore <namespace> [<target-databasename>]
function ns_dbrestore()
{
  case $1 in
    kmgetubs19)
      db_restore kmgetubs19 odoo ${2:-odoo}
    ;;
    kutuapp-test)
      db_restore kutuapp-test kutuapp ${2:-kutuapp}
    ;;
    kutuapp)
      db_restore kutuapp kutuapp ${2:-kutuapp}
    ;;
    keycloak)
      db_restore keycloak keycloak ${2:-keycloak}
  esac
}

# MAIN-Function
  if [ -z "$1" ]
  then
    usage
  else
    case $1 in
      short)
        secretbackup
        db_backup_prepare
        db_backup kutuapp kutuapp kutuapp
        db_backup kutuapp-test kutuapp kutuapp
        db_backup kmgetubs19 odoo
        db_backup keycloak keycloak keycloak
        cloudsync up
        ;;
      all)
        secretbackup
        db_backup_prepare
        db_backup kutuapp kutuapp kutuapp
        db_backup kutuapp-test kutuapp kutuapp
        db_backup kmgetubs19 odoo
        db_backup keycloak keycloak keycloak
        pvc_backup kmgetubs19
        pvc_backup keycloak
        pvc_backup kutuapp-test
        pvc_backup kutuapp
        pvc_backup sharevic
        pvc_backup pg-admin
        cluster_backup
        cloudsync up
        ;;
      clean_snapshots)
        zfs_clean_snapshots $2
        ;;
      cloudsync)
        cloudsync $2 $3
        ;;
      cluster)
        clusterbackup
        ;;
      secrets)
        secretbackup
        ;;
      dbbackup)
        db_backup kutuapp kutuapp kutuapp
        db_backup kutuapp-test kutuapp kutuapp
        db_backup kmgetubs19 odoo
        db_backup keycloak keycloak keycloak
        ;;
      dbrestore)
        ns_dbrestore $2 $3
        ;;
      restore)
        pvc_restore $2
        ;;
      backup)
        pvc_backup $2
        ;;
      secretrestore)
        secretrestore
        ;;
      privatesecretrestore)
        sealed-private-secretrestore
        ;;
      clusterrestore)
        cluster_restore
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
