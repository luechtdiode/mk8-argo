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
