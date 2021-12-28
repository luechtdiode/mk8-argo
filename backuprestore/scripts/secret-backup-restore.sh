
function secretbackup() {
  # find from mk8-argo project-root
  find ../* -name "*-secret.yaml" | xargs tar -czf secrets.tar.gz
  echo "secrets collected and saved to secrets.tar.gz"
}

function secretrestore() {
  tar -zxvf secrets.tar.gz -C .. # extract contents of secrets.tar.gz
  for file in $(tar -ztvf secrets.tar.gz  | awk -F' ' '{ if($NF != "") print $NF }' | xargs ); do
    if [ -e "../$file" ]; then
      newname=$(echo "../$file" | sed 's/-secret/-sealedsecret/')
      namespace=$(echo $newname | cut -d/ -f2 )
      kubeseal <"../$file" -o yaml >$newname -n $namespace
      echo "Secret $file restored and resealed as $newname in namespace $namespace"
    fi
  done
}