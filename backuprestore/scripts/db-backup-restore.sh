
# findPostgresPod <namespace>
function findPostgresPod()
{
  NAMESPACE="$1"
  postgrespod=$(kubectl -n $NAMESPACE get pod -l component=postgres -o jsonpath='{.items[*].metadata.name}')
  [ -z $postgrespod ] && postgrespod=$(kubectl -n $NAMESPACE get pod -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep postgres)
  echo $postgrespod
}

function db_backup_rotate()
{
  mkdir -p $(pwd)/db-backup
  mkdir -p $(pwd)/db-backup/v-1
  mkdir -p $(pwd)/db-backup/v-2
  echo "move db-dumps gen1 to gen2"
  rm -rf $(pwd)/db-backup/v-2/*
  cp $(pwd)/db-backup/v-1/*database.dump $(pwd)/db-backup/v-2/
  echo "move db-dumps actual-gen to gen1"
  rm -rf $(pwd)/db-backup/v-1/*
  cp $(pwd)/db-backup/*database.dump $(pwd)/db-backup/v-1/
  rm -f $(pwd)/db-backup/*database.dump
}

function db_backup_prepare()
{
  rm -f $(pwd)/db-backup
  mkdir -p $(pwd)/db-backup
}

# db_backup <namespace> [<pg-user> [<db-name>]]
function db_backup()
{
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

# db_restore <namespace> [<pg-user> [<db-name>]]
function db_restore()
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
