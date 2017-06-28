#!/bin/bash -x

cache_ip=${1:-172.22.101.100}
password=${2:-rancher}

echo "DOCKER_OPTS=\"\$DOCKER_OPTS --registry-mirror http://$cache_ip:5000\"" >> /etc/default/docker
service docker restart

# path to a remote share
share_path=/vagrant/.vagrant/data
mkdir -p $share_path

docker rm -f cadvisor

echo "version: 0.1
log:
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: redis
  filesystem:
    rootdirectory: /var/lib/registry
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
redis:
  addr: redis:6379
  password: $password
  db: 0
  dialtimeout: 10ms
  readtimeout: 10ms
  writetimeout: 10ms
  pool:
    maxidle: 16
    maxactive: 64
    idletimeout: 300s
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
proxy:
  remoteurl: https://registry-1.docker.io" > $share_path/config.yml

mkdir -p $share_path/redis
echo "save 300 1
requirepass \"$password\"" > $share_path/redis/redis.conf

docker run -d --name redis-mirror -p 6379 -v $share_path/redis:/data --entrypoint=/usr/local/bin/redis-server redis /data/redis.conf

docker run -d --restart=always -p 5000:5000 --name v2-mirror \
  -v $share_path:/var/lib/registry --link redis-mirror:redis registry:2 /var/lib/registry/config.yml

# Allow for --provison to clean the cattle DB
docker stop mysql
docker rm mysql

echo Install MySQL
docker run \
  -d \
  --name mysql \
  -p 3306:3306 \
  --net=host \
  -v mysql:/var/lib/mysql \
  -e MYSQL_ROOT_PASSWORD=cattle \
  mysql:5.7.18

if [ $? -eq 0 ]; then
  sleep 15
  echo Creating database
  docker exec -i mysql \
    mysql \
      --password=cattle \
      -e "CREATE DATABASE IF NOT EXISTS cattle COLLATE = 'utf8_general_ci' CHARACTER SET = 'utf8';"
fi

#Setup haproxy for Rancher HA
echo "#---------------------------------------------------------------------
# Global settings
#---------------------------------------------------------------------
global
    maxconn     100
#---------------------------------------------------------------------
# common defaults that all the 'listen' and 'backend' sections will
# use if not designated in their block
#---------------------------------------------------------------------
defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    timeout                 check 10
	option httplog clf
    option http-server-close
    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 1m
    timeout check           10s
    maxconn                 20000

listen stats
    bind 0.0.0.0:1936
    mode http
    stats enable
    stats hide-version
    stats realm Haproxy\ Statistics
    stats uri /
    stats auth Username:Password

frontend main
    mode http
    bind 0.0.0.0:80
	default_backend ha-nodes

backend ha-nodes
   default-server inter 3s fall 3 rise 2
   server ha-1 172.22.101.101:8080 check
   server ha-2 172.22.101.102:8080 check
   server ha-3 172.22.101.103:8080 check" > $share_path/haproxy.cfg

docker stop haproxy
docker rm haproxy
docker run -d --name haproxy --restart=always -p 80:80 -p 1936:1936 -v $share_path/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro haproxy:1.7

# Install nfs server
sudo mkdir -p /home/vagrant/nfs
sudo docker run -d --name nfs --restart=always --privileged --net=host -v /home/vagrant/nfs:/nfsshare -e SHARED_DIRECTORY=/nfsshare itsthenetwork/nfs-server-alpine:4

# Install git server
sudo docker run \
  -d \
  --name=git \
  -p 4000:80 \
  -v /var/git:/var/git \
  -e SERVER_NAME=172.22.101.100 \
  -e WORKER_CONNECTIONS=8 \
  -e RANCHER_SERVICE_INDEX=0 \
  --entrypoint=/bin/sh llparse/git-serve:0.5 \
    -c 'confd -onetime -backend env && service fcgiwrap start && service nginx start && tail -f /var/log/nginx/error.log'
