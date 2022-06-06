#!/bin/bash

function install()
{
  croncmd="$(pwd)/main.sh short"
  pathline="PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"
  sudo crontab -u root -l > crontabcleaned.txt
  cat crontabcleaned.txt | grep -v 'backuprestore/'
  cat crontabcleaned.txt | grep -v 'PATH='

  cp crontabcleaned.txt crontabupdated.txt
  #    22 2 * * * => every day at 02:22
  echo "$pathline >> $(pwd)/backup.log 2>&1" >> crontabupdated.txt
  echo "00,10,20,30,40,50 * * * * $croncmd >> $(pwd)/backup.log 2>&1" >> crontabupdated.txt
  sudo crontab -u root crontabupdated.txt

  sudo rm /etc/sudoers.d/mk8backuprestore
  echo "ALL ALL=(root) NOPASSWD: $(pwd)/main.sh" > $(pwd)/mk8backuprestore
  sudo pkexec visudo -c -f $(pwd)/mk8backuprestore
  sudo pkexec chown root:root $(pwd)/mk8backuprestore
  sudo pkexec mv $(pwd)/mk8backuprestore /etc/sudoers.d/mk8backuprestore
  # sudo pkexec chown root:root $(pwd)/mk8backuprestore
}

