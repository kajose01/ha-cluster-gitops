#!/usr/bin/env bash
# Shows pods being rescheduled off a failed worker (eviction delay lowered to 20s)
cd "$(dirname "$0")/.."
OUT=evidence/reschedule-test.log; : > $OUT
log() { printf '%s %s\n' "$(date +%T)" "$*" | tee -a $OUT; }
per_node() { kubectl -n dev get pods -o wide --no-headers --field-selector=status.phase=Running | awk '{print $7}' | sort | uniq -c | tr '\n' ' '; }
kubectl -n dev patch deploy webtest --type=merge -p '{"spec":{"replicas":6,"template":{"spec":{"tolerations":[
 {"key":"node.kubernetes.io/not-ready","operator":"Exists","effect":"NoExecute","tolerationSeconds":20},
 {"key":"node.kubernetes.io/unreachable","operator":"Exists","effect":"NoExecute","tolerationSeconds":20}]}}}}' >/dev/null
kubectl -n dev rollout status deploy/webtest --timeout=180s >/dev/null
log "BASELINE pods per node: $(per_node)"
log "FAILURE: stop ha-worker2"
docker stop ha-worker2 >/dev/null
for i in $(seq 1 12); do sleep 10; log "nodes-ready=$(kubectl get nodes --no-headers | grep -c ' Ready') pods per node: $(per_node)"; done
log "RECOVER: start ha-worker2"
docker start ha-worker2 >/dev/null
sleep 30; kubectl get nodes | tee -a $OUT
log "DONE"
