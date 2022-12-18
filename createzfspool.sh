# https://wiki.archlinux.org/title/ZFS/Virtual_disks

sudo apt-get install zfsutils-linux
wait

function zfsDetachPool() {
  if ! [[ "$(zfs list | grep zfspv-pool | grep -v legacy)" == */var/snap/microk8s/common/var/openebs/local ]]
  then
    sudo zfs set mountpoint=none zfspv-pool && zfs unmount /var/snap/microk8s/common/var/openebs/local
  fi
}

function zfsInitPool() {
  if ! [[ "$(zfs list | grep zfspv-pool | grep -v legacy)" == */var/snap/microk8s/common/var/openebs/local ]]
  then
    if ! [[ "$(zpool status zfspv-pool | grep state:)" == *ONLINE]]
    then
      for i in {1..3}; do sudo truncate -s 100G /zfsdisks/$i.img; done
      sudo zpool create zfspv-pool raidz1 /zfsdisks/1.img /zfsdisks/2.img /zfsdisks/3.img
    fi  
    sudo zfs set mountpoint=/var/snap/microk8s/common/var/openebs/local zfspv-pool
  fi
}
