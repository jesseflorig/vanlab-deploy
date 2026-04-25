# Operator Interface Contract: NVR Provisioning

This contract defines what an operator must provide in `group_vars/all.yml` to run the NVR provisioning playbook successfully. All values are required unless marked optional.

## Required Variables

| Variable | Type | Description |
|---|---|---|
| `nvr_host_ip` | string | IP of the NVR host — must be `10.1.10.11` |
| `nvr_frigate_admin_password` | string | Frigate web UI admin password |
| `nvr_mqtt_broker_ip` | string | Internal IP of the MQTT broker (10.1.20.x) |
| `nvr_mqtt_client_cert` | PEM string | Client cert for Frigate → broker MQTTS auth |
| `nvr_mqtt_client_key` | PEM string | Client private key (mode 0600 on host) |
| `nvr_mqtt_ca_cert` | PEM string | CA cert for broker TLS verification |
| `nvr_longhorn_nfs_ip` | string | LoadBalancer IP of Longhorn NFS share-manager |
| `nvr_longhorn_nfs_path` | string | NFS export path (e.g., `/pvc-<uuid>`) |

## Optional Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `nvr_cameras` | list | `[]` | Camera definitions (name, rtsp_url, width, height) |
| `nvr_recording_retain_days` | int | `7` | Days to retain continuous recordings on local NVMe |
| `nvr_clips_retain_days` | int | `30` | Days to retain event clips on Longhorn NFS |

## Playbook Failure Conditions

The playbook fails immediately if:
- `nvr_longhorn_nfs_ip` is empty (NFS mount cannot be configured)
- `nvr_longhorn_nfs_path` is empty (NFS mount path unknown)
- `nvr_mqtt_client_cert` or `nvr_mqtt_client_key` is empty (MQTT connection will fail)
- `/dev/hailo0` does not exist on the target host after driver installation

## Provisioning Order

This playbook has a two-phase run requirement:

**Phase A** (run first, before ArgoCD sync):
```bash
ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml --tags host-setup,hailo,frigate-config
```

**Phase B** (run after ArgoCD syncs `manifests/frigate/` and Longhorn NFS endpoint is available):
```bash
# 1. Obtain NFS endpoint
kubectl get svc -n longhorn-system -l longhorn.io/pvc-name=frigate-clips

# 2. Set nvr_longhorn_nfs_ip and nvr_longhorn_nfs_path in group_vars/all.yml

# 3. Complete provisioning
ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml --tags nfs-mount,frigate-service
```
