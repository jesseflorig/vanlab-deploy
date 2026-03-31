# Quickstart: Longhorn Distributed Block Storage

**Feature**: 006-longhorn-storage

---

## Prerequisites

1. K3s cluster is running and all nodes are Ready (`kubectl get nodes`)
2. `group_vars/all.yml` is populated (Ansible SSH credentials)
3. Helm is installed on server nodes (deployed by existing `helm` role)

---

## Step 0: Operator Note on Existing Cluster

This feature modifies K3s server configuration to disable the `local-path` storage addon. The K3s server will restart briefly. **No running workloads are affected** — existing pods and PVCs (if any) continue running during the restart.

---

## Step 1: Run services-deploy

```bash
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --ask-become-pass
```

Expected flow:
1. **Play 1 (cluster nodes)**: Install `open-iscsi`, `nfs-common`; enable `iscsid`; load `iscsi_tcp`; disable `multipathd`
2. **Play 2 (server nodes)**: Write K3s config to disable `local-storage`; restart K3s if changed; Helm install Longhorn; wait for all DaemonSets and Deployments

The Longhorn DaemonSet must start on all 6 nodes — expect 3–5 minutes for first install.

---

## Step 2: Verify Longhorn is Healthy

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# All Longhorn pods Running
kubectl get pods -n longhorn-system

# Longhorn is the only default StorageClass (local-path should have no "(default)" marker)
kubectl get storageclass

# All nodes visible in Longhorn (should show 6 nodes)
kubectl get nodes.longhorn.io -n longhorn-system
```

Expected output for StorageClass:
```
NAME                 PROVISIONER          RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
longhorn (default)   driver.longhorn.io   Retain          Immediate           true                   5m
local-path           rancher.io/local-path Delete         WaitForFirstConsumer false                 n/a (removed)
```

---

## Step 3: PVC Smoke Test

Apply a test PVC and pod to confirm Longhorn provisions and binds volumes:

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-smoke-test
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: longhorn-smoke-test
  namespace: default
spec:
  containers:
    - name: writer
      image: busybox
      command: ["/bin/sh", "-c", "echo 'longhorn works' > /data/test.txt && sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: longhorn-smoke-test
YAML
```

Wait for PVC to bind and pod to start:
```bash
kubectl wait pvc/longhorn-smoke-test --for=jsonpath='{.status.phase}'=Bound --timeout=60s
kubectl wait pod/longhorn-smoke-test --for=condition=Ready --timeout=60s
```

Verify data written:
```bash
kubectl exec longhorn-smoke-test -- cat /data/test.txt
# Expected: longhorn works
```

---

## Step 4: Persistence Test (across pod reschedule)

```bash
# Delete pod (PVC stays)
kubectl delete pod longhorn-smoke-test

# Recreate pod on potentially different node
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: longhorn-smoke-test
  namespace: default
spec:
  containers:
    - name: reader
      image: busybox
      command: ["/bin/sh", "-c", "cat /data/test.txt && sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: longhorn-smoke-test
YAML

kubectl wait pod/longhorn-smoke-test --for=condition=Ready --timeout=120s
kubectl exec longhorn-smoke-test -- cat /data/test.txt
# Expected: longhorn works
```

---

## Step 5: Cleanup

```bash
kubectl delete pod longhorn-smoke-test
kubectl delete pvc longhorn-smoke-test
```

---

## Step 6: Access Longhorn Dashboard (optional)

```bash
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80
# Open http://localhost:8080 in browser
```

Dashboard shows node storage topology, volumes, and replica health.

---

## Idempotency Check

Re-run the playbook and confirm no changes:
```bash
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --ask-become-pass
# Expect: changed=0 for all Longhorn tasks
```
