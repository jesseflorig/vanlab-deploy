# Research: Project Reorganization

**Feature**: 002-project-reorganization
**Date**: 2026-03-29

## Decision 1: OPNsense Ansible Collection

**Decision**: Use `oxlorg.opnsense` (formerly `ansibleguy.opnsense`) installed via
`requirements.yml`. Note: the collection is NOT named `community.opnsense` — that name
does not exist on Ansible Galaxy.

**Rationale**: Most actively maintained OPNsense collection; full REST API coverage;
supports check mode (`--check --diff`); well-documented module defaults pattern.

**Alternatives considered**:
- `puzzle.opnsense`: Enterprise-grade but heavier; overkill for homelab.
- Direct `uri` module calls to OPNsense API: no idempotency, no check mode support.

**Install**:
```yaml
# requirements.yml
collections:
  - name: oxlorg.opnsense
    version: ">=25.0.0"
    source: https://galaxy.ansible.com
```
```bash
ansible-galaxy collection install -r requirements.yml
```

**Connection vars** (in `group_vars/network.yml`, secrets in gitignored `all.yml`):
```yaml
opnsense_firewall: "10.1.1.1"
opnsense_api_key: "{{ vault_opnsense_api_key }}"
opnsense_api_secret: "{{ vault_opnsense_api_secret }}"
opnsense_api_verify_ssl: false   # self-signed cert on homelab router
```

**Playbook connection pattern** (runs on localhost, connects via REST API):
```yaml
- name: Configure OPNsense
  hosts: localhost
  connection: local
  gather_facts: false
  module_defaults:
    group/oxlorg.opnsense.all:
      firewall: "{{ opnsense_firewall }}"
      api_key: "{{ opnsense_api_key }}"
      api_secret: "{{ opnsense_api_secret }}"
      ssl_verify: "{{ opnsense_api_verify_ssl }}"
```

**Check mode**: Fully supported — `--check --diff` previews changes without applying them.

---

## Decision 2: Cloudflared Installation on CM5 (systemd, not Helm)

**Decision**: Install cloudflared via Cloudflare's official Debian apt repository (arm64
supported), configure as a systemd service using the tunnel token method.

**Rationale**: The current role is Helm/Kubernetes-based and cluster-dependent. The CM5
needs a native OS-level service that runs independently of K3s. The official Cloudflare
Debian repo supports arm64 and provides signed packages with standard apt idempotency.

**Alternatives considered**:
- Direct binary download from GitHub releases: works but loses apt idempotency and update
  management.
- `cloudflared service install <token>`: installs the systemd unit automatically but is
  less Ansible-idiomatic (shell command vs declarative tasks).

**Ansible task pattern**:
```yaml
- name: Add Cloudflare GPG key
  ansible.builtin.get_url:
    url: https://pkg.cloudflare.com/cloudflare-main.gpg
    dest: /usr/share/keyrings/cloudflare-main.gpg
    mode: '0644'

- name: Add Cloudflare apt repository
  ansible.builtin.apt_repository:
    repo: "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared bookworm main"
    state: present
    filename: cloudflared

- name: Install cloudflared
  ansible.builtin.apt:
    name: cloudflared
    state: present
    update_cache: true
  notify: Restart cloudflared

- name: Configure cloudflared tunnel token
  ansible.builtin.copy:
    dest: /etc/cloudflared/tunnel-token
    content: "{{ cloudflare_tunnel_token }}"
    owner: root
    group: root
    mode: '0600'
  notify: Restart cloudflared

- name: Create cloudflared systemd service
  ansible.builtin.copy:
    dest: /etc/systemd/system/cloudflared.service
    content: |
      [Unit]
      Description=Cloudflare Tunnel
      After=network.target

      [Service]
      Type=simple
      ExecStart=/usr/bin/cloudflared tunnel run --token-file /etc/cloudflared/tunnel-token
      Restart=on-failure
      RestartSec=5s

      [Install]
      WantedBy=multi-user.target
    mode: '0644'
  notify: Restart cloudflared

- name: Enable and start cloudflared
  ansible.builtin.systemd_service:
    name: cloudflared
    enabled: true
    state: started
    daemon_reload: true
```

**Tunnel health check**:
```yaml
- name: Verify cloudflared tunnel is active
  ansible.builtin.systemd_service:
    name: cloudflared
  register: cloudflared_status
  failed_when: cloudflared_status.status.ActiveState != 'active'
```

---

## Decision 3: group_vars Split Strategy

**Decision**: Split into per-category files. Shared/cross-cutting vars stay in `all.yml`
(gitignored). Category-specific vars go in named files that ARE committed (no secrets).
Secrets follow the existing `all.yml` gitignore pattern.

**Files**:
- `group_vars/all.yml` — gitignored; holds all secrets (`cloudflare_tunnel_token`,
  `opnsense_api_key`, `opnsense_api_secret`, SSH passwords)
- `group_vars/example.all.yml` — committed template showing all required keys
- `group_vars/cluster.yml` — K3s-specific non-secret vars (committed)
- `group_vars/network.yml` — OPNsense connection vars, non-secret (committed)
- `group_vars/compute.yml` — edge device vars, non-secret (committed)

**Rationale**: Keeps the existing single-file secrets pattern (operator already knows
`all.yml` is the secrets file). Per-category files hold only non-secret configuration,
making them safe to commit and easy to review.

**Alternatives considered**:
- Ansible Vault encrypted per-category files: adds vault password management overhead
  for a single-operator homelab; deferred until team grows.
- All vars in `all.yml`: current approach — loses per-category organization.

---

## Decision 4: Playbook Directory Structure

**Decision**: Move playbooks into `playbooks/<category>/` subdirectories. Keep root clean
for infrastructure files (`hosts.ini`, `requirements.yml`, `ansible.cfg`).

```
playbooks/
├── cluster/
│   ├── k3s-deploy.yml
│   └── services-deploy.yml
├── network/
│   └── network-deploy.yml
├── compute/
│   └── edge-deploy.yml
└── utilities/
    ├── check_hosts.yml
    ├── disk-health.yml
    ├── read-k3s-token.yml
    └── test-join-cmd.yml
```

**Rationale**: Clear per-category ownership. New operators immediately know where to look.
Consistent with how the device groups are organized in inventory.

**Alternatives considered**:
- Keep playbooks at root: works but becomes cluttered as device categories grow.
- Separate repos per category: excessive for a homelab; single repo with clear structure
  is simpler (Principle V).

---

## Decision 5: OPNsense Inventory Group Pattern

**Decision**: OPNsense is managed via `hosts: localhost` with REST API calls — NOT as a
standard SSH host. The `[network]` group in `hosts.ini` documents the router IP for
topology reference, but the network playbook targets `localhost`.

**Rationale**: `oxlorg.opnsense` modules run locally and call the OPNsense REST API over
HTTPS. There is no SSH connection to the router.

**Alternatives considered**:
- Adding OPNsense as an SSH target with `ansible_connection: local`: confusing and
  misleading about how the connection actually works.
