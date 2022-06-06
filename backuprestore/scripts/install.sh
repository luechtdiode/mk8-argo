#!/bin/bash

function install()
{
  croncmd="kubectl=$(which kubectl) && $(pwd)/main.sh short"
  sudo crontab -u root -l | grep -v 'backuprestore/' > crontabcleaned.txt
  cp crontabcleaned.txt crontabupdated.txt
  #    22 2 * * * => every day at 02:22
  echo "22 2 * * * $croncmd >> $(pwd)/backup.log 2>&1" >> crontabupdated.txt
  sudo crontab -u root crontabupdated.txt

  sudo rm /etc/sudoers.d/mk8backuprestore
  echo "ALL ALL=(root) NOPASSWD: $(pwd)/main.sh" > $(pwd)/mk8backuprestore
  sudo pkexec visudo -c -f $(pwd)/mk8backuprestore
  sudo pkexec chown root:root $(pwd)/mk8backuprestore
  sudo pkexec mv $(pwd)/mk8backuprestore /etc/sudoers.d/mk8backuprestore
  # sudo pkexec chown root:root $(pwd)/mk8backuprestore
}

