
function files_backup() {
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
  logfilename=file-backup.log
  echo $DATE                                                                                    >> ${BACKUP_DIR}/$logfilename
  echo "taring from $SOURCE"                                                                    >> ${BACKUP_DIR}/$logfilename
  echo "         to ${BACKUP_DIR}/$filename"                                                    >> ${BACKUP_DIR}/$logfilename
  echo $(sudo tar -cpzf ${BACKUP_DIR}/${filename} -g ${BACKUP_DIR}/${TIMESTAMP} -C ${SOURCE} .) >> ${BACKUP_DIR}/$logfilename
  cat ${BACKUP_DIR}/$logfilename
}

function files_restore() {
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
