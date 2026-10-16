#!/usr/bin/env bash
# Node failure simulation: worker down, then control-plane down, then recovery
cd "$(dirname "$0")/.."
OUT=evidence/node-failure.log; : > $OUT
log() { printf '%s %s\n' "$(date +%T)" "$*" | tee -a $OUT; }
api() { kubectl get --raw=/readyz >/dev/null 2>&1 && echo up || echo DOWN; }
snap() { log "API=$(api)  ready-nodes=$(kubectl get nodes --no-headers | grep -c ' Ready')  ready-pods=$(kubectl -n dev get pods --no-headers 2>/dev/null | grep -c '1/1 *Running')/6"; }

kubectl -n dev create deploy webtest --image=nginx:1.27-alpine --replicas=6 --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n dev set resources deploy/webtest --requests=cpu=10m,memory=16Mi >/dev/null
kubectl -n dev rollout status deploy/webtest --timeout=180s >/dev/null
log "BASELINE"; snap
kubectl -n dev get pods -o wide --no-headers | awk '{print $7}' | sort | uniq -c | tee -a $OUT

log "FAILURE 1: stop worker ha-worker"
docker stop ha-worker >/dev/null
for i in $(seq 1 14); do sleep 10; snap; done
kubectl get nodes | tee -a $OUT
kubectl -n dev get pods -o wide --no-headers | awk '{print $7}' | sort | uniq -c | tee -a $OUT

log "RECOVER: start ha-worker"
docker start ha-worker >/dev/null
for i in $(seq 1 8); do sleep 10; snap; done

log "FAILURE 2: stop control-plane ha-control-plane2 (etcd quorum 2 of 3 must hold)"
docker stop ha-control-plane2 >/dev/null
for i in $(seq 1 6); do sleep 10; snap; done
log "write test with one control plane down:"
kubectl -n dev scale deploy/webtest --replicas=8 | tee -a $OUT
sleep 15; snap
kubectl get nodes | tee -a $OUT

log "RECOVER: start ha-control-plane2"
docker start ha-control-plane2 >/dev/null
for i in $(seq 1 9); do sleep 10; snap; done
kubectl -n dev scale deploy/webtest --replicas=6 >/dev/null
kubectl -n kube-system exec etcd-ha-control-plane -- etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key member list -w table | tee -a $OUT
log "DONE"
