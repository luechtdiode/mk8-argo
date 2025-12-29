# mk8-argo

|App|Status|Entrypoint|
|---|------|----------|
|bootstrap|[![App Status](https://argo.interpolar.ch/api/badge?name=bootstrap&revision=true)](https://argo.interpolar.ch/applications/bootstrap)|n/a|
|sealed-secrets|[![App Status](https://argo.interpolar.ch/api/badge?name=sealed-secrets&revision=true)](https://argo.interpolar.ch/applications/sealed-secrets)|n/a|
|argo-cd|[![App Status](https://argo.interpolar.ch/api/badge?name=argocd&revision=true)](https://argo.interpolar.ch/applications/argocd)|[ArgoCD](https://argo.interpolar.ch/)|
|traefik|[![App Status](https://argo.interpolar.ch/api/badge?name=traefik&revision=true)](https://argo.interpolar.ch/applications/traefik)|[Traefik](https://traefik.interpolar.ch/)|
|sharevic.net|[![App Status](https://argo.interpolar.ch/api/badge?name=sharevic&revision=true)](https://argo.interpolar.ch/applications/sharevic)|[Sharevic Homepage](https://www.sharevic.net/)|
|mbq|[![App Status](https://argo.interpolar.ch/api/badge?name=mbq&revision=true)](https://argo.interpolar.ch/applications/mbq)|[Mobile Ticket queue](https://mbq.sharevic.net/)|
|kutuapp-test|[![App Status](https://argo.interpolar.ch/api/badge?name=kutuapp-test&revision=true)](https://argo.interpolar.ch/applications/kutuapp-test)|[KuTu App Test](https://kutuapp-test.sharevic.net/)|
|kutuapp|[![App Status](https://argo.interpolar.ch/api/badge?name=kutuapp&revision=true)](https://argo.interpolar.ch/applications/kutuapp)|[KuTu App](https://kutuapp.sharevic.net/)|
|kmgetubs19|[![App Status](https://argo.interpolar.ch/api/badge?name=kmgetubs19-static&revision=true)](https://argo.interpolar.ch/applications/kmgetubs19-static)|[KmGeTuBS19 Homepage](https://kmgetubs19.sharevic.net/)|

## Installation
```bash
export NIC_IPS=<iprange for metallb>
export ACCESSNAME=<storj.accessname>
export ACCESSGRANT=<storj.accessgrant>
export BACKUP_DATE=<date of backup to restore from>
bash -ci "$(curl -fsSL https://raw.githubusercontent.com/luechtdiode/mk8-argo/mk8-135-8443/setup.sh)"
```

## Troubleshooting
After bootstrapping via argo-cd, some deployments hung stuck sometimes.
Follow these steps to solve the issues:

_login into kube-dashboard (kubectl get svc -n kube-system, get NodePort, cat .kube/config get token)_

### External routing to nginx not found
* check, whether the loadbalancer MetalLB could take the given nic_ips.
* patch with metallb/metallb-ippool.yaml and the given ip-ranges

### Prometheus keeps in sync-failures
* reapply unsynced resources with options force and without schema checking and replace-option
* refresh and wait

### Secrets couldnt be unsealed
* use bootstrap.sh with restoreSecrets. If it doesnt help, reseal an push sealed-secrets to git.

### Issues with Appdata or DB restore
* got to crd argo application, delete hung apps
* source bootstrap.sh
* use boostrapViaArgo to reinstall argo-managed apps, wait until all pods are running
* use restoreAppStates only, if the disk-backups can be reused by the new installed components. In some cases, incompatiblity issues can happen. In such case, use the backuprestore scripts and restore dedicated and with manual parametrization.
* use restoreAppDBStates only, if the disk-backups can be reused by the new installed components. In some cases, incompatiblity issues can happen. In such case, use the backuprestore scripts and restore dedicated and with manual parametrization.
