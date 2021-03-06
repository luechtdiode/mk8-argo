# Storybook

*Description of how to setup a single-node cluster using microk8s*

Install Microk8s
----------------
```bash
  sudo snap remove microk8s
  snap info microk8s
  sudo snap install microk8s --classic --channel=latest/stable
  sudo usermod -a -G microk8s $USER
  sudo chown -f -R $USER ~/.kube
  su - $USER
  microk8s status --wait-ready
  alias kubectl='microk8s kubectl'
  microk8s config > ~/.kube/config
  cd $HOME
  mkdir .kube
  cd .kube
  microk8s config > config
  cd ~/microk8s-setup
  microk8s config > config.admin
  export KUBECONFIG=~/microk8s-setup/admin.config
```

On a remote ssh-client (Dev-System)
-----------------------------------
copy the admin.config to the local dev home for working with kubectl
```bash
scp roland@mars:~/microk8s-setup/admin.config .
export KUBECONFIG=~/admin.config
export KUBECONFIG=/y/docker-apps/mars/mk8-argo/admin.config
```

Edit DNS
--------
add DNS for NodeName
```bash
nano /var/snap/microk8s/current/certs/csr.conf.template
```
https://theorangeone.net/posts/lan-only-applications-with-tls/

Activate plugins
----------------
(use the two ip-addresses of cni1/2 for metallb setup)
```bash
  microk8s enable rbac dns storage openebs ingress metallb helm3 metrics-server fluentd
  sudo snap install kustomize
```

Create admin-user with its sa-token
-----------------------------------
```bash
kubectl apply -f ~/microk8s-setup/admin-user-sa.yaml
kubectl apply -f ~/microk8s-setup/admin-cluster-rolebinding.yaml
kubectl -n kube-system get secret $(kubectl -n kube-system get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}"
```

Make dashboard accessible (optional)
------------------------------------
```bash
kubectl patch svc kubernetes-dashboard -n kube-system -p '{"spec": {"type": "NodePort"}}'
```

Install OpenEBS storage
-----------------------
https://github.com/openebs/zfs-localpv
https://forums.freebsd.org/threads/my-experience-in-freebsd-backup-physical-and-virtual.79670/
```bash
microk8s enable openebs
sudo apt-get install zfsutils-linux
sudo zpool create zfspv-pool /dev/sdb
sudo zfs set mountpoint=/var/snap/microk8s/common/var/openebs/local zfspv-pool 
# unmount with sudo zfs set mountpoint=none zfspv-pool && zfs unmount /var/snap/microk8s/common/var/openebs/local 
kubectl label node mars openebs.io/rack=rack1
```
Migrate to cStore:
-------------------
https://computingforgeeks.com/deploy-and-use-openebs-container-storage-on-kubernetes/
https://vitobotta.com/2019/07/03/openebs-tips/

```
https://www.thomas-krenn.com/de/wiki/ISCSI_unter_Linux_mounten
https://manjaro.site/how-to-connect-to-iscsi-volume-from-ubuntu-20-04/

sudo apt-get update
sudo apt-get install open-iscsi
sudo systemctl enable --now iscsid
systemctl status iscsid
kubectl get blockdevice -n openebs

# connect iscsi-target as blcokdevice
sudo iscsiadm -m node -T <iqn> -p <target-ip>:3260 --login -d3
# find the new disk
sudo fdisk -l 
# logout
sudo iscsiadm -m node -u
```

Prepare Storj Cloud Storage
---------------------------
[See Storj Dashboard](https://eu1.storj.io/project-dashboard)

*Download & Install*
```bash
curl -L https://github.com/storj/storj/releases/latest/download/uplink_linux_amd64.zip -o uplink_linux_amd64.zip
unzip -o uplink_linux_amd64.zip && rm uplink_linux_amd64.zip
chmod 755 uplink
sudo mv uplink /usr/local/bin/uplink
```
*Setup*
[take access-name, api-key generated from Storj Website](https://eu1.storj.io/access-grants)
```bash
uplink setup # 2 eu1.storj.io, access-name, api-key, passphrase, passphrase, n
uplink mb sj://sharevic/ # ignore error if the bucket exists already
uplink share sj://sharevic/ --readonly=false --export-to accessgrant.txt
uplink cp sj://sharevic/manualbackup/secrets.tar.gz backuprestore/secrets.tar.gz
```

Prepare Velero
--------------
```bash
curl -L https://github.com/vmware-tanzu/velero/releases/download/v1.7.1/velero-v1.7.1-linux-amd64.tar.gz -o velero.tar.gz
tar -xvf velero.tar.gz && rm velero.tar.gz
sudo mv velero-v1.7.1-linux-amd64/velero /usr/local/bin/
```

Install via Bootstrap-Setup
---------------------------
```
helm install argocd
helm template bootstrap/ | kubectl apply -f -
```


Backup/Restore microk8s cluster
-------------------------------
https://discuss.kubernetes.io/t/recovery-of-ha-microk8s-clusters/12931/1

Actually, the script ./backuprestore/backup.sh manages all backup/restore stuff based on local pv locations (hostpath)
coming with microk8s storage and microk8s openebs.

```bash
./backuprestore/backup.sh help
```

.. otherwise ..
### Backup secrets
```bash
# cd mk8-argo project-root
sudo find ./* -name "*-secret.yaml"
sudo find ./* -name "*-secret.yaml" | xargs tar -czf secrets.tar.gz
tar -ztvf secrets.tar.gz # list contents of secrets.tar.gz
```

### Regenerate secrets
```bash
# cd mk8-argo project-root
tar -ztvf secrets.tar.gz # list contents of secrets.tar.gz
tar -zxvf secrets.tar.gz # extract contents of secrets.tar.gz
./regen-secrets.sh
```

### Recovery

1. Ensure all cluster nodes are not running with sudo snap stop microk8s or sudo microk8s stop
2. Take a backup of a known good node (in this example, node 1 or 2) and exclude the info.yaml, metadata1, metadata2 files. An example, creating a tarball of the data: `tar -c -v -z --exclude=*.yaml --exclude=metadata* -f dqlite-data.tar.gz /var/snap/microk8s/current/var/kubernetes/backend`. This will create dqlite-data.tar.gz, containing a known-good replica of the data.
3. Copy the dqlite-data.tar.gz to any nodes with older data. For example, use scp.
4. On a node(s) with non-fresh data, take the copied archive, switch to the root user with sudo su, and change directory to the / directory with `cd /.`
5. Again on the node(s) with non-fresh data, decompress the archive. If you copied the archive to the /home/ubuntu directory with scp, then run `tar zxfv /home/ubuntu/dqlite-data.tar.gz`
6. Verify that the updated files have been decompressed into /var/snap/microk8s/current/var/kubernetes, the latest sequence numbers on the data file filenames should match between hosts.
7. Prior to the next step, check the files in /var/snap/microk8s/current/var/kubernetes/backend and compare the files on each node. Make sure that the data files (the numbered dqlite files, e.g. 0000000002834690-0000000002835307 match on each host. You can check sha256sum results for each file to be sure. The list of files should match on each node. Also check the same for the snapshot-* files in the same directory. Once you are sure these files match, proceed to the next step.
8. Start each node, one at a time, starting with a server which previously had up to date data (in this example, that would be node 1 or node 2, not node 3). If all data files are now in sync, microk8s should start after a short delay, when running sudo microk8s start.

### Verification

Once each node has started, and the microk8s start command has finished running on the last node, verify each node once started successfully has finished replicating and starting up using microks8 status. After you start microk8s, it may take up to 5-10 minutes before the replication is up to date and all nodes are caught up and running, so please be aware of this, the status my show an error connecting during this time, but waiting will show the cluster has returned to full health. If you have to wait more than 10-15 minutes, validate the data files, and repeat this process as necessary.

You should also be able to issue microk8s kubectl get all -A on each node and see all cluster resources once replication has recovered to validate microk8s is back to fully health.

## Vault
https://kubevault.com/docs/v2021.10.11/welcome/