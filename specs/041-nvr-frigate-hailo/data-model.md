# Data Model: NVR Frigate + Hailo-8 Provisioning

**Feature**: 041-nvr-frigate-hailo  
**Date**: 2026-04-25

---

## Ansible Variable Interface

Variables the operator MUST set in `group_vars/all.yml` (never in Git):

```yaml
# NVR Host
nvr_host_ip: "10.1.10.11"

# Frigate auth (built-in Frigate authentication)
nvr_frigate_admin_password: "<secret>"

# MQTT
nvr_mqtt_broker_ip: "10.1.20.x"           # internal broker IP
nvr_mqtt_client_cert: |                    # PEM cert for Frigate MQTT client
  -----BEGIN CERTIFICATE-----
  ...
nvr_mqtt_client_key: |                     # PEM private key (never committed)
  -----BEGIN PRIVATE KEY-----
  ...
nvr_mqtt_ca_cert: |                        # CA cert for broker verification
  -----BEGIN CERTIFICATE-----
  ...

# Longhorn NFS mount
nvr_longhorn_nfs_ip: ""                    # populated after ArgoCD syncs PVC
nvr_longhorn_nfs_path: ""                  # e.g., /pvc-<uuid>

# Cameras (zero or more)
nvr_cameras:
  - name: "front-door"
    rtsp_url: "rtsp://user:pass@10.1.30.x:554/stream"
    width: 1920
    height: 1080
  # add entries as needed
```

Variables set in `group_vars/example.all.yml` (template, committed to Git):

```yaml
nvr_host_ip: "10.1.10.11"
nvr_frigate_admin_password: "CHANGE_ME"
nvr_mqtt_broker_ip: "CHANGE_ME"
nvr_mqtt_client_cert: "CHANGE_ME"
nvr_mqtt_client_key: "CHANGE_ME"
nvr_mqtt_ca_cert: "CHANGE_ME"
nvr_longhorn_nfs_ip: ""
nvr_longhorn_nfs_path: ""
nvr_cameras: []
```

---

## Host Filesystem Layout (NVR Host)

```
/var/lib/frigate/
├── config/
│   ├── config.yml              # Frigate config (Ansible-templated)
│   ├── certs/
│   │   ├── ca.crt              # MQTT CA cert (from group_vars)
│   │   ├── frigate-client.crt  # MQTT client cert (from group_vars)
│   │   └── frigate-client.key  # MQTT client key (from group_vars, mode 0600)
│   └── model_cache/            # HEF model files (downloaded by Frigate)
└── media/                      # local NVMe — continuous recordings only
    └── recordings/

/mnt/frigate-clips/             # Longhorn NFS mount — event clips only
```

---

## Frigate config.yml Structure (Ansible Template)

```yaml
# /var/lib/frigate/config/config.yml (j2 template)

mqtt:
  enabled: true
  host: "{{ nvr_mqtt_broker_ip }}"
  port: 8883
  tls_ca_certs: /config/certs/ca.crt
  tls_client_cert: /config/certs/frigate-client.crt
  tls_client_key: /config/certs/frigate-client.key
  topic_prefix: frigate
  client_id: frigate-nvr

detectors:
  hailo8:
    type: hailo8
    device: PCIe

model:
  path: /config/model_cache/hailo/yolov8s.hef
  input_tensor: nhwc
  input_pixel_format: rgb
  model_type: yolo-generic
  width: 640
  height: 640

record:
  enabled: true
  retain:
    days: 7
    mode: motion
  events:
    retain:
      default: 30
      mode: active_objects

clips:
  # clips are written to /media/frigate/clips → NFS mount
  retain:
    default: 30

media:
  recordings_dir: /media/frigate/recordings
  clips_dir: /media/frigate/clips     # mapped to Longhorn NFS mount

cameras:
{% for cam in nvr_cameras %}
  {{ cam.name }}:
    ffmpeg:
      inputs:
        - path: "{{ cam.rtsp_url }}"
          roles:
            - detect
            - record
    detect:
      width: {{ cam.width }}
      height: {{ cam.height }}
      fps: 5
    objects:
      track:
        - person
        - car
{% endfor %}
```

---

## Kubernetes Resources

### Namespace
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: frigate
```

### Longhorn RWX StorageClass
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-rwx
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "2"
  fsType: "ext4"
  nfsOptions: "vers=4.1,noresvport"
```

### Longhorn PVC (Clips)
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: frigate-clips
  namespace: frigate
  annotations:
    longhorn.external.share: "true"
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: longhorn-rwx
  resources:
    requests:
      storage: 50Gi
```

### Service + Endpoints (External NVR Host)
```yaml
apiVersion: v1
kind: Service
metadata:
  name: frigate
  namespace: frigate
spec:
  ports:
    - name: http
      port: 5000
      targetPort: 5000
---
apiVersion: v1
kind: Endpoints
metadata:
  name: frigate
  namespace: frigate
subsets:
  - addresses:
      - ip: 10.1.10.11
    ports:
      - name: http
        port: 5000
```

### cert-manager Certificate
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: frigate-tls
  namespace: frigate
spec:
  secretName: wildcard-fleet1-cloud-tls   # reuse existing wildcard if available
  issuerRef:
    name: letsencrypt-dns
    kind: ClusterIssuer
  dnsNames:
    - frigate.fleet1.cloud
```

### Traefik IngressRoute
```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: frigate
  namespace: frigate
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`frigate.fleet1.cloud`)
      kind: Rule
      services:
        - name: frigate
          port: 5000
  tls:
    secretName: wildcard-fleet1-cloud-tls
```

---

## systemd Unit (Ansible Template)

```ini
# /etc/systemd/system/frigate.service (j2 template)
[Unit]
Description=Frigate NVR
After=docker.service network-online.target mnt-frigate-clips.mount
Requires=docker.service mnt-frigate-clips.mount

[Service]
Restart=always
RestartSec=10
ExecStartPre=-/usr/bin/docker stop frigate
ExecStartPre=-/usr/bin/docker rm frigate
ExecStart=/usr/bin/docker run \
  --name frigate \
  --privileged \
  --shm-size=256m \
  -p 5000:5000 \
  -p 8554:8554 \
  -v /var/lib/frigate/config:/config \
  -v /var/lib/frigate/media:/media/frigate \
  -v /mnt/frigate-clips:/media/frigate/clips \
  --device /dev/hailo0:/dev/hailo0 \
  ghcr.io/blakeblackshear/frigate:stable
ExecStop=/usr/bin/docker stop frigate

[Install]
WantedBy=multi-user.target
```

---

## Ordering Dependencies

```
1. Ansible: provision NVR host (Hailo driver, Docker, base config)
   ↓
2. ArgoCD: sync manifests/frigate/ (creates namespace, PVC, Service, Endpoints, IngressRoute)
   ↓
3. Longhorn: share-manager pod starts, NFS endpoint becomes available
   ↓
4. Ansible: configure NFS mount (needs Longhorn NFS IP from step 3)
   ↓
5. Ansible: start Frigate systemd service
```

Step 4 requires the operator to set `nvr_longhorn_nfs_ip` and `nvr_longhorn_nfs_path` in `group_vars/all.yml` after ArgoCD syncs the PVC. The playbook fails with a clear error if these are empty, preventing Frigate from starting without the NFS mount.
