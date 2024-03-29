# https://wiki.archlinux.org/title/ZFS/Virtual_disks

sudo apt-get install zfsutils-linux
wait

function zfsDetachPool() {
  succ=$(sudo zfs set mountpoint=none zfspv-pool)
  succ=$(sudo zfs unmount /var/snap/microk8s/common/var/openebs/local)
  wait
  zfs list
  zpool list
}

function zfsDestroyPool() {
  succ=$(sudo zfs set mountpoint=none zfspv-pool)
  succ=$(sudo zfs unmount /var/snap/microk8s/common/var/openebs/local)
  succ=$(sudo zpool destroy -f zfspv-pool)
  succ=$(sudo rm -f /zfsdisks/zfspv-pool.img)
}

function zfsInitPool() {
  if ! [[ "$(zfs list | grep zfspv-pool | grep -v legacy)" == */var/snap/microk8s/common/var/openebs/local ]]
  then
    if ! [[ "$(zpool status zfspv-pool | grep state:)" == *ONLINE ]]
    then
      # for i in {1..3}; do sudo truncate -s 40G /zfsdisks/$i.img; done
      # sudo zpool create zfspv-pool raidz1 /zfsdisks/1.img /zfsdisks/2.img /zfsdisks/3.img
      sudo truncate -s 60G /zfsdisks/zfspv-pool.img
      sudo zpool create zfspv-pool /zfsdisks/zfspv-pool.img
    fi  
    sudo zfs set mountpoint=/var/snap/microk8s/common/var/openebs/local zfspv-pool
  fi
}
