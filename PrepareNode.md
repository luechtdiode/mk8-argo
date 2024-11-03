Install dockerized infrastructure (docker, microk8s, argo, helm, loadbalancer, traefik)
=======================================================================================

Disable Swapfile
----------------
```bash
  sudo swapoff -v /swap.img
```
Next, remove the swap file entry /swapfile swap swap defaults 0 0 from the /etc/fstab file.
```bash
  sudo rm /swapfile
```

Define snap update-times
------------------------
```
snap refresh --time
sudo snap set system refresh.timer=4:00-7:00,20:00-22:00 
```

Define snap-channel for microk8s
--------------------------------

```
sudo snap refresh microk8s --channel=latest/stable
```

Disable sleep-mode for ubuntu-server
------------------------------------
see https://en-wiki.ikoula.com/en/Disable_Ubuntu_sleep_mode

```
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```
