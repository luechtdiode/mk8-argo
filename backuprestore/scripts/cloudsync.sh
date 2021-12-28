source ./file-incremental-backup-restore.sh

# cloudsync [up | down] defaults to up
function cloudsync() {
  CLUSTER_DIR="$(pwd)/cluster-backup"
  DB_DIR="$(pwd)/db-backup"
  SOURCE="$(pwd)/volumes-backup"
  BACKUP_DIR="$(pwd)/cloud-backup"
  BUCKET="sj://mars/"
  PREFIX="manualbackup"
  CLOUD_PATH="$BUCKET$PREFIX"

  case $1 in
    down)
      uplink cp $CLOUD_PATH/secrets.tar.gz secrets.tar.gz

      rm -rf $CLUSTER_DIR
      mkdir $CLUSTER_DIR
      for file in $(uplink ls $CLOUD_PATH/cluster | awk -F/ '{ print $NF }'); do
        uplink cp $CLOUD_PATH/cluster/$file $CLUSTER_DIR/$file
      done

      for file in $(uplink ls $CLOUD_PATH/db | awk -F/ '{ print $NF }'); do
        uplink cp $CLOUD_PATH/db/$file $DB_DIR/$file
      done

      rm -rf $BACKUP_DIR
      mkdir $BACKUP_DIR
      for file in $(uplink ls $CLOUD_PATH/volumes | awk -F/ '{ print $NF }'); do
        uplink cp $CLOUD_PATH/volumes/$file $BACKUP_DIR/$file
      done

      files_restore $SOURCE $BACKUP_DIR
    ;;
    *)
      uplink rb $BUCKET --force
      uplink mb $BUCKET
      uplink cp secrets.tar.gz $CLOUD_PATH/secrets.tar.gz

      for file in $(find $CLUSTER_DIR/* -name "*.tar.gz" | xargs ); do
        uplink cp $file $CLOUD_PATH/cluster/$(echo $file | awk -F/ '{ print $NF }')
      done

      for file in $(find $DB_DIR/* -name "*.dump" | xargs ); do
        uplink cp $file $CLOUD_PATH/db/$(echo $file | awk -F/ '{ print $NF }')
      done

      # collect all pvc incremental backups to one cloud-pvc incremental backup
      echo "--------------------------------"
      echo "cloud-backup from: $SOURCE ..."
      files_backup $SOURCE $BACKUP_DIR

      for file in $(find $BACKUP_DIR/* -name "backup*.tar.gz" | xargs ); do
        uplink cp $file $CLOUD_PATH/volumes/$(echo $file | awk -F/ '{ print $NF }')
      done
    ;;
  esac
}
