# https://wiki.archlinux.org/title/ZFS/Virtual_disks

sudo apt-get install zfsutils-linux
wait

if ! [[ "$(zfs list | grep zfspv-pool | grep -v legacy)" == */var/snap/microk8s/common/var/openebs/local ]]
then
  for i in {1..3}; do sudo truncate -s 100G /zfsdisks/$i.img; done
  sudo zpool create zfspv-pool raidz1 /zfsdisks/1.img /zfsdisks/2.img /zfsdisks/3.img
  sudo zfs set mountpoint=/var/snap/microk8s/common/var/openebs/local zfspv-pool
fi
