# Quickstart & Verification: MQTT migrate to fleet1.lan

**Feature**: `056-mqtt-lan-migration` | **Date**: 2026-04-28

## Execution Order

```
1. network-deploy.yml          # Add DNAT rule 8883→30883
2. Push manifests to Gitea     # cert + IngressRouteTCP changes → ArgoCD syncs
3. nvr-provision.yml           # Update Frigate config (host → mqtt.fleet1.lan)
```

**Do not remove `mqtt.fleet1.cloud` config until Step 4 (verification) passes.**

---

## Step 1 — Apply DNAT Rule

```bash
ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml
```

Verify the DNAT rule was created (check OPNsense UI: Firewall → NAT → Port Forward, or via API).

---

## Step 2 — Commit and Push Manifest Changes

After editing `certificates.yaml` and `mosquitto-tcp-route.yaml`:

```bash
git add manifests/home-automation/prereqs/certificates.yaml \
        manifests/home-automation/prereqs/mosquitto-tcp-route.yaml \
        roles/mosquitto/defaults/main.yml
git commit -m "feat(mqtt): migrate broker hostname to mqtt.fleet1.lan"
git push gitea 056-mqtt-lan-migration
```

ArgoCD syncs automatically. Monitor at `https://argocd.fleet1.cloud`.

Wait for cert-manager to reissue `mosquitto-tls` (typically < 60 seconds). Confirm:

```bash
kubectl get certificate -n home-automation mosquitto-tls
# STATUS: Ready
kubectl get secret -n home-automation mosquitto-tls -o jsonpath='{.data.tls\.crt}' \
  | base64 -d | openssl x509 -noout -text | grep -A5 "Subject Alternative"
# Should show: mqtt.fleet1.lan, mosquitto.home-automation.svc.cluster.local, mosquitto.home-automation
```

---

## Step 3 — Verify mqtt.fleet1.lan Connectivity

From any host that can resolve fleet1.lan (management laptop or NVR host):

```bash
# DNS resolution check
dig mqtt.fleet1.lan @10.1.1.1
# Expect: 10.1.20.11

# TLS connectivity check (requires mosquitto-clients)
mosquitto_pub \
  --cafile /path/to/home-automation-ca.crt \
  --cert   /path/to/client.crt \
  --key    /path/to/client.key \
  -h mqtt.fleet1.lan -p 8883 \
  -t test/migration -m "lan-ok" -d
# Expect: successful publish, no TLS errors
```

**SC-001**: DNS resolves to `10.1.20.11` ✓
**SC-002**: Connection + publish completes within 5 seconds ✓

---

## Step 4 — Deploy Frigate Config Update

```bash
ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml
```

Verify in Frigate UI (`https://frigate.fleet1.lan`) that MQTT status shows connected. Check Frigate logs:

```bash
ssh nvr "docker logs frigate 2>&1 | grep -i mqtt | tail -20"
# Expect: "mqtt connected" or similar, no "connection refused" or TLS errors
```

**SC-003**: Home Assistant MQTT-based automations and device states remain functional ✓
**SC-005**: Zero MQTT disruptions during migration ✓

---

## Step 5 — Retire mqtt.fleet1.cloud

Only proceed after Step 4 passes.

1. Remove `HostSNI('mqtt.fleet1.cloud')` route (already replaced in Step 2 — nothing further needed).
2. Verify `mqtt.fleet1.cloud` is not a public Cloudflare DNS record:
   ```bash
   dig mqtt.fleet1.cloud
   # Expect: NXDOMAIN or only internal override
   ```
3. The `mqtt.fleet1.cloud` Unbound override (if any exists) was managed outside `network-deploy.yml`. Verify:
   ```bash
   # From OPNsense UI: Services → Unbound DNS → Host Overrides
   # Look for any explicit mqtt.fleet1.cloud entry and remove it if present.
   ```

**SC-004**: `mqtt.fleet1.cloud` returns NXDOMAIN on internal DNS lookup ✓
