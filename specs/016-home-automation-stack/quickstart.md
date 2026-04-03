# Quickstart: Home Automation Stack

**Branch**: `016-home-automation-stack`

---

## Prerequisites

- K3s cluster with Longhorn, cert-manager (`letsencrypt-prod` ClusterIssuer), and Traefik deployed
- `group_vars/all.yml` populated with the new secrets (see below)
- DNS records created: `hass.fleet1.cloud`, `node-red.fleet1.cloud`, `influxdb.fleet1.cloud`, `mqtt.fleet1.cloud` → edge device / Traefik node IP

---

## 1. Add Secrets to group_vars/all.yml

```yaml
# InfluxDB
influxdb_admin_password: <strong-password>
influxdb_admin_token: <random-64-char-token>
influxdb_org_id: ""  # Leave blank initially; fill after first InfluxDB login

# Mosquitto
mosquitto_password_entry: "homeassistant:<hashed-password>"
# Generate hash: mosquitto_passwd -b /dev/stdout homeassistant <password>

# Node-RED
node_red_admin_password_bcrypt: "<bcrypt-hash>"
# Generate: node -e "require('bcryptjs').hash('yourpassword', 8, (e,h) => console.log(h))"
```

---

## 2. Deploy

```bash
# Deploy the full home automation stack
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags home-automation

# Or deploy individual services
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags mosquitto
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags influxdb
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags hass
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags node-red
```

**Note**: Deploy in order: `mosquitto` → `influxdb` → `hass` → `node-red`. The `mosquitto` role creates the `home-automation-ca` ClusterIssuer that other roles depend on.

---

## 3. Post-Deploy: InfluxDB Setup

1. Open `https://influxdb.fleet1.cloud` and log in with `influxdb_admin_password`
2. Copy the **Organization ID** from the URL (format: `https://influxdb.../orgs/<hex-id>`)
3. Add `influxdb_org_id: <hex-id>` to `group_vars/all.yml`
4. Re-run the `hass` role to write the org ID to HA's `secrets.yaml`:
   ```bash
   ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags hass
   ```

---

## 4. Post-Deploy: Home Assistant Setup

1. Open `https://hass.fleet1.cloud` and complete the onboarding wizard
2. Go to **Settings → Devices & Services → Add Integration → MQTT**
3. Broker: `mosquitto.home-automation.svc.cluster.local`, Port: `8883`, TLS: enabled
4. Use the client certificate files (mounted from `home-assistant-mqtt-client` Secret)

---

## 5. Verify

```bash
# Check all pods are Running
kubectl get pods -n home-automation

# Verify Mosquitto rejects plaintext
mosquitto_pub -h mqtt.fleet1.cloud -p 8883 -t test -m hello
# Expected: Connection error (no cert)

# Verify MQTTS with valid cert
mosquitto_pub \
  --cafile ca.crt --cert client.crt --key client.key \
  -h mqtt.fleet1.cloud -p 8883 -t test -m hello
# Expected: success

# Check InfluxDB data after HA starts
kubectl exec -n home-automation deploy/influxdb -- \
  influx query 'from(bucket:"homeassistant") |> range(start:-5m) |> limit(n:5)'
```

---

## 6. IoT Device Client Certificates

To issue a client certificate for an IoT device:

```yaml
# Add to manifests or apply via kubectl (for devices on 10.1.40.x)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: device-sensor-01
  namespace: home-automation
spec:
  secretName: device-sensor-01-cert
  issuerRef:
    name: home-automation-ca
    kind: ClusterIssuer
  commonName: sensor-01
  usages:
    - client auth
```

Extract cert/key from the Secret and provision to the device:
```bash
kubectl get secret device-sensor-01-cert -n home-automation \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > sensor-01.crt
kubectl get secret device-sensor-01-cert -n home-automation \
  -o jsonpath='{.data.tls\.key}' | base64 -d > sensor-01.key
kubectl get secret device-sensor-01-cert -n home-automation \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt
```
