# Backup solution with velero and storj-plugin
https://docs.storj.io/dcs/how-tos/kubernetes-backup-via-velero

## Install the uplink cli
```bash
curl -L https://github.com/storj/storj/releases/latest/download/uplink_linux_amd64.zip -o uplink_linux_amd64.zip
unzip -o uplink_linux_amd64.zip
chmod 755 uplink
sudo mv uplink /usr/local/bin/uplink
uplink setup # and use api-key provided by storj-ui
```

### Create backup bucket with access grant
```bash
uplink mb sj://sharevic
uplink share sj://sharevic/ --readonly=false --export-to accessgrant.txt
```

## Install the Velero plugin for Tardigrade (a.k.a. Storj DCS)
```bash
curl -L https://github.com/vmware-tanzu/velero/releases/download/v1.7.1/velero-v1.7.1-linux-amd64.tar.gz -o velero.tar.gz
tar -xvf velero.tar.gz

BUCKET=sharevic
ACCESS=$(cat accessgrant.txt)
velero install --provider tardigrade \
    --plugins storjlabs/velero-plugin:latest \
    --bucket $BUCKET \
    --backup-location-config accessGrant=$ACCESS \
    --no-secret
```
## Execute Backups
```bash
velero backup create backupname
```
