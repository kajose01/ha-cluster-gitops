# HA Kubernetes Cluster with RBAC, etcd Backups and GitOps

A highly available Kubernetes cluster (3 control-plane + 2 worker nodes) with RBAC, component validation, etcd snapshots, node-failure simulations, and GitOps delivery with ArgoCD from `dev`, `staging` and `production` branches.

## 1. Problem Statement

XYZ Corporation needs a resilient cluster that survives node failures and a controlled delivery process. The task is to:

- build a cluster with 3 control-plane and 2 worker nodes,
- configure RBAC, validate components and back up etcd,
- simulate node failures and observe the behaviour,
- manage environments with `dev`, `staging` and `production` branches,
- deploy through GitOps (ArgoCD).

## 2. Important Note: Simulated HA

The cluster is built with **kind**, so every "node" is a Docker container on one EC2 instance (2 vCPU, 8 GB). The Kubernetes HA design is real: three kubeadm control planes with stacked etcd (three voting members), an HA load balancer in front of the three API servers, and two workers. It does **not** protect against loss of the host machine. Production HA needs separate machines.

## 3. Repository Layout

    cluster/    kind-ha.yaml (3 control-plane + 2 worker)
    rbac/       namespaces, roles and bindings
    scripts/    validate.sh, etcd-backup.sh, test-rbac.sh, node-failure.sh, reschedule-test.sh
    apps/       webapp manifests (per-environment copies live on the branches)
    argocd/     one Application per environment
    evidence/   outputs of every script

**Branches:** `main` holds the tooling. `dev`, `staging` and `production` each hold `apps/webapp` with 1, 2 and 3 replicas. ArgoCD tracks the branch that matches each environment.

## 4. Steps to Build and Run

    kind create cluster --config cluster/kind-ha.yaml --wait 300s
    ./scripts/validate.sh                  # component and etcd validation
    ./scripts/etcd-backup.sh               # snapshot to ./backups (git-ignored)
    kubectl apply -f rbac/rbac.yaml && ./scripts/test-rbac.sh
    ./scripts/node-failure.sh              # worker, then control-plane failure
    ./scripts/reschedule-test.sh           # pod rescheduling after worker loss
    kubectl create namespace argocd
    kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.0/manifests/install.yaml
    kubectl apply -f argocd/

## 5. Results

**Cluster and etcd.** Five nodes Ready (3 control-plane, 2 workers). etcd has three started members, none learner, and three healthy endpoints (12 to 15 ms). A snapshot was saved and verified (`evidence/etcd-snapshot-status.txt`). Snapshots contain all Secrets, so `.db` files are git-ignored.

**RBAC** (`evidence/rbac-test.log`): 8 of 8 checks passed. A developer can manage `dev` only, a viewer can read everywhere and write nowhere, an unknown user gets nothing.

**Node failure** (`evidence/node-failure.log`, `evidence/reschedule-test.log`):

| Test | Result |
|---|---|
| Worker stopped, default settings | Detected as NotReady after about 50 s. The worker returned before the 300 s eviction delay, so no pods moved. |
| Worker stopped, eviction delay set to 20 s | NotReady after about 41 s. About 70 s after the stop, the pods from the dead node were recreated on the surviving worker. |
| One control plane stopped | API stayed up, a scale from 6 to 8 succeeded, etcd kept quorum (2 of 3). After the restart all three members were started again. |

Pods on a stopped node keep showing `Running` until Kubernetes evicts them, so the test counts them separately.

**GitOps** (`evidence/gitops-sync.txt`, `gitops-demo.txt`, `selfheal.txt`): three Applications are Synced and Healthy with 1, 2 and 3 replicas. A commit to `dev` changed the cluster with no `kubectl apply`, and a manual scale-down in `production` was reverted by self-heal.

## 6. Optimization Techniques Used

- **Quorum-aware testing:** the failure script stops at most one control plane, so etcd quorum is never lost.
- **Tuned eviction delay** on test pods (20 s) to show rescheduling in minutes instead of waiting for the 300 s default.
- **Least-privilege RBAC** with a namespaced Role and a read-only ClusterRole, verified with `kubectl auth can-i`.
- **Automated sync with prune and self-heal**, so Git stays the source of truth.
- **Small, repeatable scripts** that write their own evidence files.
- **Snapshots outside Git:** only the status report is committed.
- **Resource requests and limits** on the demo workload.

## 7. Challenges Faced and Solutions

| Challenge | Solution |
|---|---|
| The first cluster creation failed while joining the third control plane on a 2 vCPU host. | Stopped other workloads (k3s), raised the inotify limits and retried. The second attempt succeeded. The logs show the third etcd member catching up as a learner before promotion. |
| The etcd image has no `etcdutl`, so snapshot verification failed. | Used `etcdctl snapshot status` instead. |
| The first node-failure test did not show rescheduling. | The node came back before the 300 s default eviction delay. Added a second test with a 20 s toleration. |
| Stopped-node pods still looked Running, which made counts misleading. | Documented that eviction is delayed and compared pods per node. |
| True multi-machine HA does not fit on one instance. | Used kind and stated the limitation openly. |
