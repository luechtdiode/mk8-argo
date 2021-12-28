#!/bin/bash
cd "$(dirname "$0")"

PVCROOT=/var/snap/microk8s/common/var/openebs/local
kubectl=$(which kubectl)

source ./scripts/secret-backup-restore.sh
source ./scripts/db-backup-restore.sh
source ./scripts/file-incremental-backup-restore.sh
source ./scripts/pvc-backup-restore.sh
source ./scripts/cluster-backup-restore.sh
source ./scripts/cloudsync.sh

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

function install()
{
  croncmd="kubectl=$(which kubectl) && $(pwd)/main.sh"
  sudo crontab -u root -l | grep -v 'backuprestore/main.sh' > crontabcleaned.txt
  cp crontabcleaned.txt crontabupdated.txt
  echo "* * * * * $croncmd >> $(pwd)/backup.log 2>&1" >> crontabupdated.txt
  sudo crontab -u root crontabupdated.txt
  # sudo cp crontabupdated.txt /etc/crontab
}

# MAIN-Function
  if [ -z "$1" ]
  then
    secretbackup
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
        secret_restore
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
