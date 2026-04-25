# Quickstart: NVR Frigate + Hailo-8 Provisioning

## Prerequisites

- [ ] NVR host at `10.1.10.11` is reachable via SSH with sudo access
- [ ] Hailo-8 PCIe card is physically installed
- [ ] Longhorn is running in the cluster (`kubectl get pods -n longhorn-system`)
- [ ] ArgoCD is running and syncing from Gitea
- [ ] `group_vars/all.yml` exists (copy from `group_vars/example.all.yml` if not)

## Step 1: Set Required Variables

Edit `group_vars/all.yml` and populate the `nvr_*` variables. Leave `nvr_longhorn_nfs_ip` and `nvr_longhorn_nfs_path` empty for now. MQTT cert material is read automatically from the cluster — no PEM values to paste.

```yaml
nvr_host_ip: "10.1.10.11"
nvr_frigate_admin_password: "your-password"
nvr_mqtt_broker_ip: "10.1.20.x"
```

## Step 2: Run Phase A (Host Software)

```bash
ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml --tags host-setup,hailo
```

This installs Docker, Hailo driver, and udev rules. The Frigate config is deferred to Phase B so it can read the MQTT client cert issued by cert-manager after ArgoCD sync.

**Verify Hailo driver**:
```bash
ssh nvr-user@10.1.10.11 "hailortcli fw-control identify"
# Should print Hailo-8 firmware info and device serial
```

## Step 3: Apply Cluster-Side Manifests

Push the branch and let ArgoCD sync, or apply manually for initial bootstrap:

```bash
git push gitea 041-nvr-frigate-hailo
# After PR merge → ArgoCD syncs manifests/frigate/ automatically
```

Monitor sync:
```bash
kubectl get pods -n longhorn-system -l "longhorn.io/component=share-manager"
# Wait for share-manager-frigate-clips pod to be Running
```

## Step 4: Obtain Longhorn NFS Endpoint

```bash
kubectl get svc -n longhorn-system -l "longhorn.io/pvc-name=frigate-clips" -o jsonpath='{.items[0].spec.clusterIP}'
kubectl get pv $(kubectl get pvc frigate-clips -n frigate -o jsonpath='{.spec.volumeName}') -o jsonpath='{.spec.nfs.path}'
```

Set these values in `group_vars/all.yml`:
```yaml
nvr_longhorn_nfs_ip: "<cluster-ip-from-above>"
nvr_longhorn_nfs_path: "<path-from-above>"
```

## Step 5: Run Phase B (Frigate Config + NFS Mount + Service Start)

```bash
ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml --tags frigate-config,nfs-mount,frigate-service
```

## Step 6: Verify

```bash
# Check Frigate is running
ssh nvr-user@10.1.10.11 "systemctl status frigate"

# Check Hailo-8 is active detector (not CPU)
ssh nvr-user@10.1.10.11 "docker logs frigate 2>&1 | grep -i hailo"

# Check NFS clips mount
ssh nvr-user@10.1.10.11 "mountpoint /mnt/frigate-clips && df -h /mnt/frigate-clips"

# Access web UI
curl -k https://frigate.fleet1.cloud
```

## Step 7: Apply HA Integration Config

The playbook outputs a `ha-frigate-config.txt` file in the repo root (gitignored). Apply its contents to Home Assistant's `configuration.yaml` or via the UI integrations page.

## Re-Provisioning

Safe to re-run at any time:
```bash
ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml
```
