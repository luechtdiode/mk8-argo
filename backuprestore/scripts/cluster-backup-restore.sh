
function cluster_backup()
{
  mkdir -p ./cluster-backup
  sudo microk8s stop
  tar -c -v -z --exclude=*.yaml --exclude=metadata* -f ./cluster-backup/dqlite-data.tar.gz /var/snap/microk8s/current/var/kubernetes/backend
  sudo microk8s start
}

function cluster_restore()
{
  DQLITE_BACKUP=$(pwd)/cluster-backup/dqlite-data.tar.gz
  cd /.
  su $whoami
    microk8s stop
    tar zxfv $DQLITE_BACKUP
    microk8s start
  exit
  cd -
}