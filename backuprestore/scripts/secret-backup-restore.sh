
function secretbackup() {
  maxageSeconds=$(echo 365*24*3600 | bc)
  # find from mk8-argo project-root (backuprestore/..)
  
  echo "deleting previous collected secret-private files in local filesystem:"
  find ../* -type f -name "*-secret-private.yaml"
  find ../* -type f -name "*-secret-private.yaml" | xargs rm -f

  for pair in $(kubectl get secret --all-namespaces -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o jsonpath='{range .items[*]}{ ..namespace }{","}{..name}{","}{..creationTimestamp}{"\n"}{end}'); do
    IFS=, read -r namespace secret creationTimestamp <<< "$pair"
    age="$(($(date +%s) - $(date -d $creationTimestamp +%s)))"
    #if [ $maxageSeconds -ge $age ]
    #then
      echo "getting sealed-secret private-key $secret from $namespace"
      mkdir -p ../$namespace/templates
      kubectl get secret $secret -n $namespace -o yaml > ../$namespace/templates/backup-$secret-secret-private.yaml
    #else
    #  echo "NOT getting sealed-secret private-key $secret from $namespace."
    #  echo " MaxAge in seconds $maxageSeconds."
    #  echo " Age in seconds    $age."
    #fi
  done

  # find_custom_secrets_in_cluster
  find_sealed_secrets_in_cluster

  find ../* -type f -name "*-secret.yaml" -o -name "*-secret-*.yaml" | xargs tar -czf secrets.tar.gz
  echo "secrets collected and saved to secrets.tar.gz"
}

function find_sealed_secrets_in_cluster() {
  echo "deleting previous collected backup-*-secret files in local filesystem:"
  find ../* -type f -name "backup-*-secret.yaml"
  find ../* -type f -name "backup-*-secret.yaml" | xargs rm -f
  for pair in $(kubectl get sealedsecret --all-namespaces -o go-template='{{range .items }}{{printf "%s,%s\n" .metadata.namespace .metadata.name }}{{end}}')
  do
    IFS=, read -r namespace secret <<< "$pair"
    echo "getting secret of sealedsecret $secret from $namespace"
    mkdir -p ../$namespace/templates
    kubectl get secret $secret -n $namespace -o yaml > ../$namespace/templates/backup-$secret.yaml
  done
}

# unused ...
function find_custom_secrets_in_cluster() {
  echo "deleting previous collected backup-*-secret files in local filesystem:"
  find ../* -type f -name "backup-*-secret.yaml"
  find ../* -type f -name "backup-*-secret.yaml" | xargs rm -f
  for pair in $(kubectl get secret --field-selector type=Opaque --all-namespaces -o go-template='{{range .items }}{{if .metadata.labels }}{{else if eq .metadata.name "memberlist" }}{{else}}{{printf "%s,%s\n" .metadata.namespace .metadata.name }}{{end}}{{end}}')
  do
    IFS=, read -r namespace secret <<< "$pair"
    echo "getting custom-secret $secret from $namespace"
    mkdir -p ../$namespace/templates
    kubectl get secret $secret -n $namespace -o yaml > ../$namespace/templates/backup-$secret.yaml
  done
}

function restoreSecret() {
  [[ $1 == */backup-*-secret.yaml ]] && applySecret $1
  newname=$(echo "../$1" | sed 's/-secret/-sealedsecret/')
  namespace=$(echo $newname | cut -d/ -f2 )

  kubeseal <"../$1" -o yaml >$newname -n $namespace
  echo "Secret $1 restored and resealed as $newname in namespace $namespace"
}

function applySecret() {
  namespace=$(echo $1 | cut -d/ -f1 )

  kubectl -n $namespace apply -f "../$1"
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
