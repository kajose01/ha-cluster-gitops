#!/usr/bin/env bash
# Component validation for the HA cluster
set -u
echo "== nodes";            kubectl get nodes -o wide
echo; echo "== control-plane pods"; kubectl -n kube-system get pods -l tier=control-plane -o wide
echo; echo "== API health";  kubectl get --raw='/readyz?verbose' | tail -8
echo; echo "== component status"; kubectl get --raw='/livez?verbose' | grep -E "etcd|ok$" | head -5
echo; echo "== etcd members"
kubectl -n kube-system exec etcd-ha-control-plane -- etcdctl \
  --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
  member list -w table
echo; echo "== etcd endpoint health"
kubectl -n kube-system exec etcd-ha-control-plane -- etcdctl \
  --endpoints=https://172.18.0.6:2379,https://172.18.0.4:2379,https://172.18.0.3:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key endpoint health -w table
