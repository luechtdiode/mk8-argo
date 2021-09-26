#!/bin/bash

docker build -t nginx_naxsi:v1.7 .

docker tag nginx_naxsi:v1.7 luechtdiode/nginx-naxsi:1.7
docker push luechtdiode/nginx-naxsi:1.7