#!/bin/bash

set -uex

IMAGE=kontena-ipam
TAG=${KONTENA_IPAM_TAG:-latest}

docker rm kontena-ipam-nspawn || true
docker build -t ${IMAGE}:${TAG} .
docker create --name kontena-ipam-nspawn ${IMAGE}:${TAG}

test -d /var/lib/machines/$IMAGE:$TAG.new && rm -rf /var/lib/machines/$IMAGE:$TAG.new
mkdir /var/lib/machines/$IMAGE:$TAG.new
docker export kontena-ipam-nspawn | tar -x -C /var/lib/machines/$IMAGE:$TAG.new

docker rm kontena-ipam-nspawn || true

#mkdir /var/lib/machines/$IMAGE:$TAG.new/var/lib/journal

test -d /var/lib/machines/$IMAGE:$TAG && rm -rf /var/lib/machines/$IMAGE:$TAG
mv /var/lib/machines/$IMAGE:$TAG.new /var/lib/machines/$IMAGE:$TAG
