# Quickstart: Verify Loki Log Aggregation

After running `services-deploy.yml`, use these steps to verify the full log pipeline is working.

## 1. Check Loki is running

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki
# Expected: loki-0   Running   1/1
```

## 2. Check Alloy DaemonSet is running on all nodes

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=alloy
# Expected: one pod per node (6 pods), all Running
```

## 3. Verify Loki is receiving logs (via port-forward)

```bash
kubectl port-forward svc/loki 3100:3100 -n monitoring &
curl -s "http://localhost:3100/loki/api/v1/labels" | python3 -m json.tool
# Expected: {"status":"200", "data":["app","namespace","node_name", ...]}
```

## 4. Query logs via Grafana

1. Open `https://grafana.fleet1.cloud`
2. Navigate to **Explore** (compass icon)
3. Select **Loki** from the datasource dropdown
4. Run a label query: `{namespace="argocd"}`
5. Expected: ArgoCD pod logs appear within the last few minutes

## 5. Verify pod logs from all namespaces

Test each critical namespace:

| Query | Expected result |
|-------|----------------|
| `{namespace="argocd"}` | ArgoCD controller, server, repo-server logs |
| `{namespace="monitoring"}` | Prometheus, Grafana, Alertmanager logs |
| `{namespace="longhorn-system"}` | Longhorn manager, CSI, UI logs |
| `{namespace="traefik"}` | Traefik ingress controller logs |

## 6. Verify node-level system logs

```
{job="systemd-journal"} |= "k3s"
```

Expected: K3s service start/stop events, kubelet messages.

## 7. Verify log persistence (pre/post restart)

```bash
# Record a timestamp
date

# Restart a pod
kubectl rollout restart deployment/argocd-server -n argocd

# Wait for it to come back
kubectl rollout status deployment/argocd-server -n argocd

# Query Grafana with the timestamp from step 1 as the start time
# Logs from before the restart should still be present
```

## 8. Verify Longhorn PVC is bound

```bash
kubectl get pvc -n monitoring -l app.kubernetes.io/name=loki
# Expected: loki   Bound   ...   20Gi   longhorn
```
