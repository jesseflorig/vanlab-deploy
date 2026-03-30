# Research: Cluster Provisioning and Internet Exposure

**Feature**: 003-cluster-tunnel-expose
**Date**: 2026-03-29

---

## Decision 1: K3s Agent Join Fix

**Decision**: Fix the agent join issue by (1) adding both a TCP port check and an HTTP `/readyz` API probe after server install, (2) waiting for the token file to exist before reading it, (3) replacing the `creates:` guard with a `service_facts` check, and (4) using `groups['servers'][0]` instead of the hard-coded `'node1'` hostname reference.

**Root cause of the existing bug**: The current playbook uses `creates: /etc/systemd/system/k3s-agent.service` as the idempotency guard. The K3s installer writes this file very early — before the agent has confirmed it joined. If the agent install fails after creating the service file, subsequent runs silently skip the entire install. Additionally, there is no wait between server install and agent join, so agents race the API startup (which takes 15–45s on Raspberry Pi hardware).

**Fix pattern** (confirmed against k3s-io/k3s-ansible and community practice):

```yaml
# In servers play — after K3s server install:
- name: Wait for K3s API port to be reachable
  ansible.builtin.wait_for:
    host: "{{ ansible_host }}"
    port: 6443
    delay: 5
    timeout: 120

- name: Wait for K3s API server to pass readiness check
  ansible.builtin.uri:
    url: "https://{{ ansible_host }}:6443/readyz"
    validate_certs: false
    status_code: [200, 401]   # 401 = API up, rejecting anonymous auth — sufficient to proceed
  register: k3s_api_ready
  until: k3s_api_ready.status in [200, 401]
  retries: 24
  delay: 5

- name: Wait for K3s token file to exist
  ansible.builtin.wait_for:
    path: /var/lib/rancher/k3s/server/token
    state: present
    timeout: 30

- name: Read K3s node token
  ansible.builtin.slurp:
    src: /var/lib/rancher/k3s/server/token
  register: k3s_token_raw

- name: Set K3s token fact
  ansible.builtin.set_fact:
    k3s_node_token: "{{ k3s_token_raw['content'] | b64decode | regex_replace('\n', '') }}"

# In agents play — service_facts idempotency guard:
- name: Gather service facts
  ansible.builtin.service_facts:

- name: Install K3s agent
  ansible.builtin.shell: |
    curl -sfL https://get.k3s.io | \
      K3S_URL=https://{{ k3s_master_ip }}:6443 \
      K3S_TOKEN={{ hostvars[groups['servers'][0]]['k3s_node_token'] }} \
      INSTALL_K3S_EXEC="--flannel-iface={{ k3s_flannel_iface }}" sh -
  when: >
    ansible_facts.services['k3s-agent.service'] is not defined
    or ansible_facts.services['k3s-agent.service']['state'] != 'running'

- name: Wait for agent node to appear Ready
  ansible.builtin.shell: |
    k3s kubectl get node {{ inventory_hostname }} \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
  register: node_ready
  until: node_ready.stdout == "True"
  retries: 30
  delay: 10
  delegate_to: "{{ groups['servers'][0] }}"
  become: true
  changed_when: false
```

**Key refinements from research**:
- Two-stage API readiness: TCP port check then HTTP `/readyz` probe — Raspberry Pi hardware takes longer to initialize
- `wait_for path:` on token file — token is written asynchronously after K3s service starts
- `regex_replace('\n', '')` instead of `trim` for token stripping (community convention from k3s-ansible)
- `service_facts` guard handles the partial-install case: service file exists but agent not running → re-install
- `groups['servers'][0]` instead of `'node1'` — more robust if server hostnames change

**Alternatives considered**:
- `creates:` guard: rejected — doesn't handle failed-first-attempt case (service file created but agent never joined).
- `kubectl get node` pre-check via delegation: works but `service_facts` is more idiomatic Ansible and handles upgrade scenarios too.
- Use `k3s-io/k3s-ansible` community role: rejected — adds an external dependency per Principle V (Simplicity).

---

## Decision 2: Disable K3s Built-in Traefik

**Decision**: Pass `--disable traefik` in `INSTALL_K3S_EXEC` on server nodes. This prevents K3s from deploying its own Traefik via a HelmChart CRD into `kube-system`.

**Rationale**: K3s ships with Traefik v2 as a built-in addon. If we deploy our own Traefik v3 via Helm into the `traefik` namespace without disabling the built-in, both instances compete for port 80 via ServiceLB (klipper-lb). The built-in must be disabled before Helm deployment.

```yaml
- name: Install K3s server
  shell: |
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik \
      --write-kubeconfig-mode 644 \
      --flannel-iface={{ k3s_flannel_iface }}" sh -
  args:
    creates: /etc/systemd/system/k3s.service
```

**Note**: If the cluster was previously provisioned without `--disable traefik`, the built-in Traefik manifest at `/var/lib/rancher/k3s/server/manifests/traefik.yaml` must be removed and the `HelmChart` CRD deleted before re-running.

**Alternatives considered**:
- Use K3s built-in Traefik v2: rejected — less control over version and values; v2 is being superseded by v3.
- Patch the built-in HelmChart CRD values: rejected — fragile and non-idiomatic.

---

## Decision 3: Traefik Helm Values (HTTP-only for Cloudflare Backend)

**Decision**: Deploy Traefik v3 via Helm with a values file that enables only the `web` (HTTP/80) entrypoint as a LoadBalancer service. The `websecure` (443) entrypoint is disabled externally since Cloudflare terminates TLS.

**Rationale**: The Cloudflare tunnel sends plain HTTP to the backend (Traefik). Enabling TLS on the cluster side for the tunnel leg would require a certificate on Traefik that Cloudflare trusts — unnecessary complexity for a homelab. Cloudflare handles the public-internet HTTPS; the CM5→Traefik hop is internal.

**Key values**:

```yaml
# roles/traefik/files/values.yaml
service:
  type: LoadBalancer

ports:
  web:
    port: 80
    expose:
      default: true
    exposedPort: 80
  websecure:
    expose:
      default: false
    tls:
      enabled: false

ingressRoute:
  dashboard:
    enabled: false

providers:
  kubernetesIngress:
    enabled: true
    publishedService:
      enabled: true

logs:
  access:
    enabled: true
```

**Helm deploy with `--wait`**: Use `helm upgrade --install --wait --timeout 3m` so the Ansible task blocks until Traefik pods are Ready. The current role lacks this flag.

**Constitution VI note**: The edge device (10.1.10.x) → Traefik (10.1.20.x) hop crosses a VLAN boundary over plain HTTP. This is a justified exception for this feature: the Cloudflare tunnel already encrypts the public-internet leg, and the internal hop traverses a trusted network segment. A follow-on feature should add HTTPS on the Traefik side and configure the tunnel to use `https://` backend with certificate verification.

**Alternatives considered**:
- Enable TLS on Traefik with a self-signed cert and configure tunnel as `https://` with `noTLSVerify: true`: provides encryption but complexity cost is not justified at this stage.
- Use Traefik v2 chart: rejected — v3 is current; v2 annotation format differs.

---

## Decision 4: Whoami Deployment Pattern

**Decision**: Create a `roles/whoami/` role that applies a Kubernetes manifest (Deployment + Service + Ingress) to the cluster using `kubectl apply`. The manifest is stored in `roles/whoami/files/whoami.yaml`.

**Rationale**: The `traefik/whoami` image is the canonical lightweight test app for Traefik setups — it returns all request headers, making it easy to verify routing and tunnel forwarding. Using `kubectl apply` with a static manifest file is simple and idempotent (Principle V).

**Ingress annotation for Traefik v3**:

```yaml
annotations:
  traefik.io/router.entrypoints: web
```

The old v2 annotation prefix (`traefik.ingress.kubernetes.io/`) is deprecated in v3. The `ingressClassName: traefik` field is also required.

**Namespace**: Deploy whoami into the `traefik` namespace for co-location simplicity. Traefik's `kubernetesIngress` provider watches all namespaces by default.

**Idempotency**: `kubectl apply` is idempotent by design — re-running produces no changes if the manifests are unchanged.

**Alternatives considered**:
- Use `kubernetes.core` Ansible collection: adds a Galaxy dependency; `kubectl apply` achieves the same with no extra install.
- Use a Traefik `IngressRoute` CRD instead of standard `Ingress`: gives more Traefik-specific control but standard `Ingress` is simpler and sufficient (Principle V).

---

## Decision 5: Cluster Status Visibility from Control Machine (FR-008)

**Decision**: Add a final task to `k3s-deploy.yml` that runs `kubectl get nodes -o wide` on node1 (via `delegate_to`) and displays the result with `debug`. This gives the operator node status without manual SSH.

**Rationale**: FR-008 requires the operator to verify cluster state from the Ansible control machine. Running kubectl via Ansible delegation achieves this without requiring kubeconfig to be copied to the control machine.

```yaml
- name: Display cluster node status
  command: kubectl get nodes -o wide
  delegate_to: node1
  register: node_status
  changed_when: false

- name: Show node status
  debug:
    msg: "{{ node_status.stdout_lines }}"
```

**Alternatives considered**:
- Copy kubeconfig to Ansible control machine: useful for ongoing cluster management but out of scope for this feature.
- Use `kubernetes.core.k8s_info`: requires collection install.
