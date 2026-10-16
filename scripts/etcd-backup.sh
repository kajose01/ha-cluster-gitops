#!/usr/bin/env bash
# Takes an etcd snapshot, verifies it, copies it to ./backups (git-ignored)
set -euo pipefail
cd "$(dirname "$0")/.."
TS=$(date +%Y%m%d-%H%M%S); NAME="etcd-$TS.db"
E="kubectl -n kube-system exec etcd-ha-control-plane --"
CERTS="--cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"
$E etcdctl --endpoints=https://127.0.0.1:2379 $CERTS snapshot save /var/lib/etcd/$NAME
$E etcdctl snapshot status /var/lib/etcd/$NAME -w table 2>/dev/null | tee evidence/etcd-snapshot-status.txt
docker cp ha-control-plane:/var/lib/etcd/$NAME backups/$NAME
ls -lh backups/$NAME
