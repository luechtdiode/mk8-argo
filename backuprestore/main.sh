#!/bin/bash
cd "$(dirname "$0")"

PVCROOT=/var/snap/microk8s/common/var/openebs/local
kubectl="$(which microk8s) kubectl"
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
    
    BACKUP:
    all                     => make cluster-, secret-, db- and incremental pvc-backup per month from all volumes of the registered namespaces
    short                   => make backup of secrets and db of the registered namespaces and push new bucked with cloudsync up
    backup <namespace>      => make incremental pvc-backup per month from all volumes of the specified namespace
    dbbackup                => make zero-downtime db-backup or registered databases
    secrets                 => collects all *secret.yaml from the sibling-folders (namespaces)
    cluster                 => make backup of cluster resources (kubernetes dqlite-data)
    
    RESTORE:
    restore <namespace>            => restore the backed up volumes of the specified namespace
    restore <namespace> <pvcname>  => restore a dedicated pvc of the specified namespace
    dbrestore <namespace>          => restore the database from its last stored backup
    dbrestore <namespace> <dbname> => restore database from a dedicated database
    dbrestore <namespace> <dbname> <to dbname> => restore database to a dedicated database
    secretrestore           => extracts secrets from backup and reseals the sealedsecrets
    privatesecretrestore    => extracts private secrets from backup and applies in the namespaces
    clusterrestore          => restores cluster resouces (kubernetes dqlite-data)
    
    CLOUD-SYNC:
    cloudsync               => save all current backups to storj bucket
                               [[up | down] bucket-qualifier] defaults to up today 
    cloudsync up            => save all current backups to storj bucket
    cloudsync down          => download all backups from storj bucket
    
    MAINTENANCE:
    clean_snapshots <namespace> => clean zfs-snapshots
    install                 => installs daily backup starting at 02:22
    uninstall               => uninstalls daily backup scheduling
    help                    => print usage
  '
}

# ns_restore <namespace> [<source-databasename> [<target-databasename>]]
function ns_dbrestore()
{
  case $1 in
    kmgetubs19)
      db_restore kmgetubs19 odoo ${2:-odoo} ${3:-odoo}
    ;;
    kutuapp-test)
      db_restore kutuapp-test kutuadmin ${2:-kutuapp} ${3:-kutuapp}
    ;;
    kutuapp)
      db_restore kutuapp kutuadmin ${2:-kutuapp} ${3:-kutuapp}
    ;;
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
        db_backup kutuapp kutuadmin kutuapp
        db_backup kutuapp-test kutuadmin kutuapp
        db_backup kmgetubs19 odoo
        pvc_backup traefik
        cloudsync up
        ;;
      all)
        secretbackup
        db_backup_prepare
        db_backup kutuapp kutuadmin kutuapp
        db_backup kutuapp-test kutuadmin kutuapp
        db_backup kmgetubs19 odoo
        pvc_backup traefik
        pvc_backup kmgetubs19
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
        db_backup kutuapp kutuadmin kutuapp
        db_backup kutuapp-test kutuadmin kutuapp
        db_backup kmgetubs19 odoo
        ;;
      dbrestore)
        ns_dbrestore $2 $3 $4
        ;;
      restore)
        pvc_restore $2 $3
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
      uninstall)
        uninstall
        echo "daily backup from crontab removed for backup-location $(pwd)"
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
