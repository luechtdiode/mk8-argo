#!/bin/bash

function install()
{
  croncmd="$(pwd)/main.sh short"
  pathline="PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"
  envparams="UPLINK_CONFIG_DIR=/home/$(whoami)/.config/storj/uplink"
  sudo crontab -u root -l  \
    | grep -v 'backuprestore/' \
    | grep -v 'PATH=' \
    > crontabcleaned.txt

  cp crontabcleaned.txt crontabupdated.txt
  #    22 2 * * * => every day at 02:22
  echo "$pathline" >> crontabupdated.txt
  echo "00,10,20,30,40,50 * * * * $envparams $croncmd >> $(pwd)/backup.log 2>&1" >> crontabupdated.txt
  sudo crontab -u root crontabupdated.txt

  sudo rm /etc/sudoers.d/mk8backuprestore
  echo "ALL ALL=(root) NOPASSWD: $(pwd)/main.sh" > $(pwd)/mk8backuprestore
  sudo pkexec visudo -c -f $(pwd)/mk8backuprestore
  sudo pkexec chown root:root $(pwd)/mk8backuprestore
  sudo pkexec mv $(pwd)/mk8backuprestore /etc/sudoers.d/mk8backuprestore
  # sudo pkexec chown root:root $(pwd)/mk8backuprestore
}

