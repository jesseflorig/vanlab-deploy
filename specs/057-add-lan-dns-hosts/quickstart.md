# Quickstart: fleet1.lan Infrastructure DNS Host Records

## Prerequisites

- Current branch: `057-add-lan-dns-hosts`
- OPNsense API credentials present in untracked `group_vars/all.yml`
- LAN access to OPNsense at `10.1.1.1`
- `dig` available on the validation machine

## Plan Validation

Review the desired records:

```bash
sed -n '1,220p' specs/057-add-lan-dns-hosts/data-model.md
```

## Apply

Run the network playbook from the repository root:

```bash
ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml
```

Re-run the same command to verify idempotency. The second run should not create duplicate Unbound
host overrides or change unrelated DNS records.

If the OPNsense Web GUI still serves its default self-signed certificate for
`opnsense.fleet1.lan`, deploy the existing `fleet1.lan` wildcard certificate to
the Web GUI certificate slot:

```bash
ansible-playbook -i hosts.ini playbooks/network/opnsense-webgui-cert-deploy.yml
```

If OPNsense reports a potential DNS rebind attack when opening
`https://opnsense.fleet1.lan`, browse to `https://10.1.1.1`, then set:

- Page: System -> Settings -> Administration
- Field: Alternate Hostnames
- Value to include: `opnsense.fleet1.lan`

This preserves DNS rebind protection while allowing the LAN management FQDN.

## DNS Validation

Validate each hostname from a LAN client:

```bash
dig opnsense.fleet1.lan @10.1.1.1 +short
dig sw-main.fleet1.lan @10.1.1.1 +short
dig sw-poe-1.fleet1.lan @10.1.1.1 +short
dig sw-poe-2.fleet1.lan @10.1.1.1 +short
dig sw-poe-3.fleet1.lan @10.1.1.1 +short
```

Expected output:

```text
10.1.1.1
10.1.1.10
10.1.1.11
10.1.1.12
10.1.1.13
```

## Persistence Validation

After an OPNsense Unbound restart or reconfigure, repeat the DNS validation commands. All five
hostnames should continue resolving to the same addresses.

## Validation Results

Recorded on 2026-04-28 from this repository workspace.

- Syntax validation passed:
  `ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml --syntax-check`
- Initial apply completed successfully:
  `ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml`
- The initial apply created all five infrastructure Unbound host overrides and reconfigured Unbound.
- Idempotency re-run completed successfully with all five infrastructure host override creation items skipped and Unbound reconfigure skipped.
- DNS validation from this client is blocked or unreachable: each direct query to `@10.1.1.1` timed out with `no servers could be reached`.
- Administrative hostname connection checks from this client are blocked by hostname resolution timeouts.
- Persistence validation remains pending until DNS queries against `10.1.1.1` succeed from a LAN client using OPNsense DNS.

Follow-up on 2026-04-28:

- OPNsense Unbound settings contain all five enabled `A` host override rows with the expected addresses.
- `/api/unbound/service/status` reports `status: stopped`.
- `/api/unbound/service/start` and `/api/unbound/service/restart` return success-style responses, but status remains `stopped`.
- `/api/core/service/search` lists `unbound` with `running: 0`; `/api/core/service/restart/unbound` returns `result: failed`.
- The API user cannot read resolver logs from `/api/diagnostics/log/core/resolver` (`403 Forbidden`), so the immediate blocker is diagnosing why Unbound will not stay running on OPNsense.

Resolution on 2026-04-28:

- The startup failure was isolated to the existing `*.fleet1.lan` wildcard host override combined with explicit host overrides in the same domain.
- The network playbook now disables the incompatible wildcard override and creates explicit Traefik records for known LAN service names.
- Unbound starts successfully after reconfigure/start.
- DNS validation succeeded:
  - `opnsense.fleet1.lan` -> `10.1.1.1`
  - `sw-main.fleet1.lan` -> `10.1.1.10`
  - `sw-poe-1.fleet1.lan` -> `10.1.1.11`
  - `sw-poe-2.fleet1.lan` -> `10.1.1.12`
  - `sw-poe-3.fleet1.lan` -> `10.1.1.13`
- Explicit Traefik service records such as `mqtt.fleet1.lan` and `hass.fleet1.lan` resolve to `10.1.20.11`.
- Arbitrary unlisted names under `fleet1.lan` no longer resolve because the wildcard override is intentionally disabled.
- Administrative connection attempts resolved to the expected management IPs. Switch HTTPS availability varies by device, but curl showed the expected target IP before refusal/timeout.

Web GUI TLS follow-up on 2026-04-28:

- `playbooks/network/opnsense-webgui-cert-deploy.yml` imports the existing Kubernetes secret
  `traefik/fleet1-lan-wildcard-tls` into the OPNsense Web GUI certificate entry through the
  Trust API and restarts the Web GUI.
- The Trust API update must address the certificate UUID, not the legacy Web GUI cert refid.
- Validation succeeded:
  - `curl -sS -o /dev/null -w '%{http_code} %{ssl_verify_result} %{remote_ip}\n' https://opnsense.fleet1.lan`
    returned `200 0 10.1.1.1`
  - Verbose curl showed issuer `CN=fleet1-lan-ca` and SAN match against `*.fleet1.lan`.
- OPNsense may still require `opnsense.fleet1.lan` in Web GUI Alternate Hostnames;
  this setting is stored at `system.webgui.althostnames` and is not exposed through the
  OPNsense REST API used by this playbook.
