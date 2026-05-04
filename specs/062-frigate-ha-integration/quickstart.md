# Quickstart: Frigate Home Assistant Integration

## Deployment Steps

### Step 1: Install HACS (One-time)

Access the Home Assistant pod and run the HACS installation script:

```bash
kubectl exec -it -n home-automation statefulset/home-assistant -- bash -c "wget -O - https://get.hacs.xyz | bash -"
```

### Step 2: Restart Home Assistant

Restart HA to pick up the HACS component:

```bash
kubectl rollout restart statefulset/home-assistant -n home-automation
```

### Step 3: Install Frigate Integration (HACS UI or Manual)

**Option A: HACS UI (Preferred)**
1. Log in to the Home Assistant UI (`https://hass.fleet1.cloud`).
2. Go to **HACS** in the sidebar.
3. Click **Integrations** → **Explore & Download Repositories**.
4. Search for "Frigate" and click **Download**.

**Option B: Manual (CLI)**
If the UI is inaccessible, you can install the integration via CLI:
```bash
kubectl exec -n home-automation statefulset/home-assistant -- bash -c "cd /config/custom_components && wget https://github.com/blakeblackshear/frigate-hass-integration/archive/refs/tags/v5.15.2.zip -O frigate.zip && unzip frigate.zip && mv frigate-hass-integration-5.15.2/custom_components/frigate . && rm -rf frigate-hass-integration-5.15.2 frigate.zip"
```

### Step 4: Restart Home Assistant
Restart HA to pick up the component:
```bash
kubectl rollout restart statefulset/home-assistant -n home-automation
```

### Step 5: Apply Configuration as Code

The integration will be configured using HA Packages. Update `manifests/home-automation/prereqs/config-extra.yaml` to include the `frigate:` configuration:

```yaml
data:
  frigate.yaml: |
    frigate:
      host: http://10.1.10.11:5000
```

Apply and sync via ArgoCD:

```bash
git add manifests/home-automation/prereqs/config-extra.yaml
git commit -m "feat: add frigate integration to home assistant"
git push gitea 062-frigate-ha-integration
```

### Step 6: Finalize in HA UI

1. Go to **Settings** → **Devices & Services**.
2. Click **Add Integration** and search for **Frigate**.
3. It should auto-detect the configuration from the YAML package. Confirm the setup.

## Verification

- Check the **Devices** list for your cameras (e.g., `camera.front_door`).
- Verify binary sensors update when motion is detected in Frigate.
- Open the **Media Browser** and ensure you can see "Frigate" recordings.
