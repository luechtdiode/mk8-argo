#!/bin/sh
for file in $(tar -ztvf secrets.tar.gz  | awk -F' ' '{ if($NF != "") print $NF }' | xargs ); do
  if [ -e "$file" ]; then
    newname=$(echo "$file" | sed 's/-secret/-sealedsecret/')
    namespace=$(echo $newname | cut -d/ -f2 )
    kubeseal <$file -o yaml >$newname -n $namespace
  fi
done

