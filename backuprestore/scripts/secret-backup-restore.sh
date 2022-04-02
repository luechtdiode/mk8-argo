
function secretbackup() {
  # find from mk8-argo project-root (backuprestore/..)
  for pair in $(kubectl get secret --all-namespaces -l sealedsecrets.bitnami.com/sealed-secrets-key -o jsonpath='{range .items[*]}{ ..namespace }{","}{..name}{"\n"}{end}'); do
    IFS=, read -r namespace secret <<< "$pair"
    echo "getting sealed-secret private-key $secret from $namespace"
    mkdir -p ../$namespace/templates
    kubectl get secret $secret -n $namespace -o yaml > ../$namespace/templates/backup-$secret-secret-private.yaml
  done
  
  find ../* -type f -name "*-secret.yaml" -o -name "*-secret-content.yaml" | xargs tar -czf secrets.tar.gz
  echo "secrets collected and saved to secrets.tar.gz"
}

function restoreSecret() {
  newname=$(echo "../$1" | sed 's/-secret/-sealedsecret/')
  namespace=$(echo $newname | cut -d/ -f2 )

  kubeseal <"../$1" -o yaml >$newname -n $namespace
  echo "Secret $1 restored and resealed as $newname in namespace $namespace"
}

function applySecret() {
  namespace=$(echo $1 | cut -d/ -f2 )

  kubectl -n $namespace apply -f <"../$1"
  echo "Secret $1 applied in namespace $namespace"
}

function secretrestore() {
  tar -zxvf secrets.tar.gz -C .. # extract contents of secrets.tar.gz
  for file in $(tar -ztvf secrets.tar.gz  | awk -F' ' '{ if($NF != "") print $NF }' | xargs ); do
    [[ $file == *-secret.yaml ]] && [[ -e "../$file" ]] && echo $(restoreSecret $file)
  done
}

function sealed-private-secretrestore() {
  tar -zxvf secrets.tar.gz -C .. # extract contents of secrets.tar.gz
  for file in $(tar -ztvf secrets.tar.gz  | awk -F' ' '{ if($NF != "") print $NF }' | xargs ); do
    [[ $file == *-secret-private.yaml ]] && [[ -e "../$file" ]] && echo $(applySecret $file)
  done
}