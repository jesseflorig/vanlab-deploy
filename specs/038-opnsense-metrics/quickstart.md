# Quickstart: OPNsense Metrics Validation

## Prerequisites
- OPNsense API user created with required ACL grants
- `opnsense_api_key` and `opnsense_api_secret` set in `group_vars/all.yml`
- Sealed Secrets controller running (`kubectl get pods -n kube-system | grep sealed-secrets`)

## Step 1: Verify Exporter Reaches OPNsense

```bash
# Test API reachability from a cluster node (before deploying the pod)
curl -sku "<key>:<secret>" https://10.1.1.1/api/core/firmware/status | python3 -m json.tool
# Expect: JSON with firmware status fields — not a 401 or connection refused
```

## Step 2: Generate and Commit SealedSecret

```bash
ansible-playbook -i hosts.ini playbooks/utilities/seal-secrets.yml --tags opnsense-exporter
git add manifests/monitoring/prereqs/sealed-secrets.yaml
git commit -m "feat(038): add opnsense-exporter SealedSecret"
git push gitea 038-opnsense-metrics
```

## Step 3: Apply Grafana Dashboard (Ansible)

```bash
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags monitoring
# Expect: Grafana Helm release upgraded, dashboard 21113 provisioned
```

## Step 4: Register ArgoCD Apps

```bash
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags argocd-bootstrap
# Expect: monitoring-prereqs and monitoring-apps Applications created in ArgoCD
```

## Step 5: Verify ArgoCD Sync

```bash
kubectl get applications -n argocd | grep monitoring
# Expect: monitoring-prereqs  Synced  Healthy
#         monitoring-apps     Synced  Healthy

kubectl get pods -n monitoring | grep opnsense
# Expect: opnsense-exporter-<hash>  1/1  Running
```

## Step 6: Verify Metrics Endpoint

```bash
# Port-forward to the exporter pod
kubectl port-forward -n monitoring deploy/opnsense-exporter 8080:8080 &
curl -s http://localhost:8080/metrics | grep opnsense_interfaces
# Expect: lines like:
# opnsense_interfaces_received_bytes_total{interface="em0"} 1.23e+09
# opnsense_interfaces_transmitted_bytes_total{interface="em0"} 4.56e+08
kill %1
```

## Step 7: Verify Prometheus Scrapes

```bash
# In Prometheus UI (https://prometheus.fleet1.cloud)
# Query: up{job="opnsense-exporter"}
# Expect: value 1
```

## Step 8: Verify Grafana Dashboard

1. Open `https://grafana.fleet1.cloud`
2. Navigate to Dashboards → search "OPNsense"
3. Dashboard gnetId 21113 should appear auto-provisioned
4. Select time range "Last 1 hour" — panels should show interface traffic, gateway status, protocol stats

## Rollback

```bash
# Remove ArgoCD Applications (ArgoCD will delete the managed resources)
kubectl delete application -n argocd monitoring-apps monitoring-prereqs

# Revert Grafana dashboard entry in Helm values
git revert HEAD  # revert the values.yaml.j2 change
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags monitoring
```
