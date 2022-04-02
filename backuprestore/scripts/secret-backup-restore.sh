
function secretbackup() {
  # find from mk8-argo project-root
  find ../* -type f -name "*-secret.yaml" -o -name "*-secret-content.yaml" | xargs tar -czf secrets.tar.gz
  echo "secrets collected and saved to secrets.tar.gz"
}

function restoreSecret() {
  kubeseal <"../$1" -o yaml >$2 -n $3
  echo "Secret $1 restored and resealed as $2 in namespace $3"
}

function secretrestore() {
  tar -zxvf secrets.tar.gz -C .. # extract contents of secrets.tar.gz
  for file in $(tar -ztvf secrets.tar.gz  | awk -F' ' '{ if($NF != "") print $NF }' | xargs ); do
    if [ -e "../$file" ]; then
      newname=$(echo "../$file" | sed 's/-secret/-sealedsecret/')
      namespace=$(echo $newname | cut -d/ -f2 )
      echo $(restoreSecret $file $newname $namespace)
      # kubeseal <"../$file" -o yaml >$newname -n $namespace
      # echo "Secret $file restored and resealed as $newname in namespace $namespace"
    fi
  done
}

# ** Please be patient while the chart is being deployed **

# You should now be able to create sealed secrets.

# 1. Install the client-side tool (kubeseal) as explained in the docs below:

#     https://github.com/bitnami-labs/sealed-secrets#installation-from-source

# 2. Create a sealed secret file running the command below:

#     kubectl create secret generic secret-name --dry-run=client --from-literal=foo=bar -o [json|yaml] | \
#     kubeseal \
#       --controller-name=sealed-secrets \
#       --controller-namespace=default \
#       --format yaml > mysealedsecret.[json|yaml]

# The file mysealedsecret.[json|yaml] is a commitable file.

# If you would rather not need access to the cluster to generate the sealed secret you can run:

#     kubeseal \
#       --controller-name=sealed-secrets \
#       --controller-namespace=default \
#       --fetch-cert > mycert.pem

# to retrieve the public cert used for encryption and store it locally. You can then run 'kubeseal --cert mycert.pem' instead to use the local cert e.g.

#     kubectl create secret generic secret-name --dry-run=client --from-literal=foo=bar -o [json|yaml] | \
#     kubeseal \
#       --controller-name=sealed-secrets \
#       --controller-namespace=default \
#       --format [json|yaml] --cert mycert.pem > mysealedsecret.[json|yaml]

# 3. Apply the sealed secret

#     kubectl create -f mysealedsecret.[json|yaml]

# Running 'kubectl get secret secret-name -o [json|yaml]' will show the decrypted secret that was generated from the sealed secret.

# Both the SealedSecret and generated Secret must have the same name and namespace.