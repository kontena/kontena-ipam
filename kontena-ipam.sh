#!/bin/bash

set -uex

MACHINE=kontena-ipam
DIRECTORY=/var/lib/machines/${MACHINE}:${KONTENA_IPAM_VERSION}

if [ ! -d $DIRECTORY ]; then
  docker rm kontena-ipam || true
  docker create --name kontena-ipam ${KONTENA_IPAM_IMAGE}:${KONTENA_IPAM_VERSION}
  mkdir $DIRECTORY.new
  docker export kontena-ipam | tar -x -C $DIRECTORY.new
  docker rm kontena-ipam || true

  mv $DIRECTORY.new $DIRECTORY
fi

SETENV=("--setenv=NODE_ID=${NODE_ID:-$HOSTNAME}")

[ -n "${PUMA_DEBUG:-}" ] && SETENV+=("--setenv=PUMA_DEBUG=$PUMA_DEBUG")
[ -n "${LOG_LEVEL:-}" ] && SETENV+=("--setenv=LOG_LEVEL=$LOG_LEVEL")
[ -n "${ETCD_ENDPOINT:-}" ] && SETENV+=("--setenv=ETCD_ENDPOINT=$ETCD_ENDPOINT")
[ -n "${KONTENA_IPAM_SUPERNET:-}" ] && SETENV+=("--setenv=KONTENA_IPAM_SUPERNET=$KONTENA_IPAM_SUPERNET")
[ -n "${KONTENA_IPAM_SUBNET_LENGTH:-}" ] && SETENV+=("--setenv=KONTENA_IPAM_SUBNET_LENGTH=$KONTENA_IPAM_SUBNET_LENGTH")

exec /usr/bin/systemd-nspawn --machine $MACHINE \
  --directory $DIRECTORY --read-only --link-journal=no \
  --chdir /app "${SETENV[@]}" \
  -- bundle exec --keep-file-descriptors puma \
      -b unix:///run/docker/plugins/kontena-ipam.sock
