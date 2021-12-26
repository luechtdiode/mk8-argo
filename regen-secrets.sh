#!/bin/sh
for file in $(tar -ztvf secrets.tar.gz  | awk -F' ' '{ if($NF != "") print $NF }' | xargs ); do
  if [ -e "$file" ]; then
    newname=$(echo "$file" | sed 's/-secret/-sealedsecret/')
    kubeseal <$file -o yaml >$newname
  fi
done

