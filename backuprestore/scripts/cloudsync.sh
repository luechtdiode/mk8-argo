source ./scripts/file-incremental-backup-restore.sh

function findUplinkConfigDir() {
  if [ -z $UPLINK_CONFIG_DIR ];
  then
    echo "~/.config/storj/uplink"
  else
    echo "$UPLINK_CONFIG_DIR"
  fi
}

UPLINK_CONFIG_DIR=$(findUplinkConfigDir)

echo "uplink config dir found at $UPLINK_CONFIG_DIR"

# _downSync CLOUD_PATH, CLUSTER_DIR, DB_DIR, BACKUP_DIR
function _downSync() {
  CLOUD_PATH=$1

  CLUSTER_DIR=$3
  DB_DIR=$4
  BACKUP_DIR=$5
  SOURCE="$(pwd)/volumes-backup"

  uplink --config-dir $UPLINK_CONFIG_DIR --interactive false --progress false cp $CLOUD_PATH/secrets.tar.gz secrets.tar.gz

  rm -rf $CLUSTER_DIR
  mkdir $CLUSTER_DIR
  for file in $(uplink --config-dir $UPLINK_CONFIG_DIR ls $CLOUD_PATH/cluster/ | tail -n +2 | awk '{ print $NF }'); do
    uplink --config-dir $UPLINK_CONFIG_DIR --interactive false --progress false cp $CLOUD_PATH/cluster/$file $CLUSTER_DIR/$file
  done

  for file in $(uplink --config-dir $UPLINK_CONFIG_DIR ls $CLOUD_PATH/db/ | tail -n +2 | awk '{ print $NF }'); do
    uplink --config-dir $UPLINK_CONFIG_DIR --interactive false --progress false cp $CLOUD_PATH/db/$file $DB_DIR/$file
  done

  rm -rf $BACKUP_DIR
  mkdir $BACKUP_DIR
  for file in $(uplink --config-dir $UPLINK_CONFIG_DIR ls $CLOUD_PATH/volumes/ | tail -n +2 | awk '{ print $NF }'); do
    uplink --config-dir $UPLINK_CONFIG_DIR --interactive false --progress false cp $CLOUD_PATH/volumes/$file $BACKUP_DIR/$file
  done

  files_restore $SOURCE $BACKUP_DIR
}

# _upSync $CLOUD_PATH $CLUSTER_DIR $DB_DIR $BACKUP_DIR
function _upSync() {
  CLOUD_PATH=$1

  CLUSTER_DIR=$2
  DB_DIR=$3
  BACKUP_DIR=$4
  SOURCE="$(pwd)/volumes-backup"

  uplink --config-dir $UPLINK_CONFIG_DIR --interactive false --progress false cp secrets.tar.gz $CLOUD_PATH/secrets.tar.gz

  for file in $(find $CLUSTER_DIR/* -name "*.tar.gz" | xargs ); do
    uplink --config-dir $UPLINK_CONFIG_DIR --interactive false --progress false cp $file $CLOUD_PATH/cluster/$(echo $file | awk -F/ '{ print $NF }')
  done

  for file in $(find $DB_DIR/* -name "*.dump" | xargs ); do
    echo  $file | awk -F"$DB_DIR" '{ print $NF }'
    uplink --config-dir $UPLINK_CONFIG_DIR --interactive false --progress false cp $file $CLOUD_PATH/db$(echo $file | awk -F"$DB_DIR" '{ print $NF }')
  done

  # collect all pvc incremental backups to one cloud-pvc incremental backup
  echo "--------------------------------"
  echo "cloud-backup from: $SOURCE ..."
  files_backup $SOURCE $BACKUP_DIR

  for file in $(find $BACKUP_DIR/* -name "backup*.tar.gz" | xargs ); do
    uplink --config-dir $UPLINK_CONFIG_DIR --interactive false --progress false cp $file $CLOUD_PATH/volumes/$(echo $file | awk -F/ '{ print $NF }')
  done  
}

# cloudsync [[up | down] bucket-qualifier] defaults to up today
function cloudsync() {
  printf -v BUCKET_DATE '%(%Y-%m-%d)T' -1
  printf -v BUCKET_MONTH '%(%Y-%m)T' -1
  printf -v BUCKET_YEAR '%(%Y)T' -1
  BUCKET_DATE=${2:-$BUCKET_DATE}
  BUCKET_DATE=$BUCKET_DATE | awk '{$1=$1};1'
  CLUSTER_DIR="$(pwd)/cluster-backup"
  DB_DIR="$(pwd)/db-backup"
  BACKUP_DIR="$(pwd)/cloud-backup-${BUCKET_DATE}"
  PREFIX="manualbackup"

  case $1 in
    down)
      BUCKET="sj://mars-${BUCKET_DATE}/"
      CLOUD_PATH="$BUCKET$PREFIX"

      if [ -z $1 ]
      then
        LATEST_BACKUP="sj://$(uplink --config-dir $UPLINK_CONFIG_DIR ls | grep mars  | tail -n +2 | awk '{ print $NF }' | sort -r | head -n 1)/"
        CLOUD_PATH="$LATEST_BACKUP$PREFIX"
      fi
      _downSync $CLOUD_PATH, $CLUSTER_DIR, $DB_DIR, $BACKUP_DIR
    ;;
    *)
      BUCKETLIST="$(uplink --config-dir $UPLINK_CONFIG_DIR ls | grep mars  | tail -n +2 | awk '{ print $NF }' | sort -r | grep -v $BUCKET_YEAR)/"
      for OBSBCKT in $BUCKETLIST
      do
        echo "test for removal: $OBSBCKT ..."
        if [[ "$OBSBCKT" =~ ^mars-[0-9]{4}-[0-9]{2}$ ]]; then
          echo "removing $OBSBCKT ..."
          uplink --config-dir $UPLINK_CONFIG_DIR rb "sj://$OBSBCKT" --force
        fi
      done

      BUCKETLIST="$(uplink --config-dir $UPLINK_CONFIG_DIR ls | grep mars  | tail -n +2 | awk '{ print $NF }' | sort -r | grep -v $BUCKET_MONTH)/"
      for OBSBCKT in $BUCKETLIST
      do
        echo "test for removal: $OBSBCKT ..."
        if [[ "$OBSBCKT" =~ ^mars-[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
          echo "removing $OBSBCKT ..."
          uplink --config-dir $UPLINK_CONFIG_DIR rb "sj://$OBSBCKT" --force
        fi
      done

      BUCKET="sj://mars-${BUCKET_YEAR}/"
      CLOUD_PATH="$BUCKET$PREFIX"
      uplink --config-dir $UPLINK_CONFIG_DIR rb $BUCKET --force
      uplink --config-dir $UPLINK_CONFIG_DIR mb $BUCKET
      _upSync $CLOUD_PATH $CLUSTER_DIR $DB_DIR $BACKUP_DIR

      BUCKET="sj://mars-${BUCKET_MONTH}/"
      CLOUD_PATH="$BUCKET$PREFIX"
      uplink --config-dir $UPLINK_CONFIG_DIR rb $BUCKET --force
      uplink --config-dir $UPLINK_CONFIG_DIR mb $BUCKET
      _upSync $CLOUD_PATH $CLUSTER_DIR $DB_DIR $BACKUP_DIR

      BUCKET="sj://mars-${BUCKET_DATE}/"
      CLOUD_PATH="$BUCKET$PREFIX"
      uplink --config-dir $UPLINK_CONFIG_DIR rb $BUCKET --force
      uplink --config-dir $UPLINK_CONFIG_DIR mb $BUCKET
      _upSync $CLOUD_PATH $CLUSTER_DIR $DB_DIR $BACKUP_DIR
    ;;
  esac
}
