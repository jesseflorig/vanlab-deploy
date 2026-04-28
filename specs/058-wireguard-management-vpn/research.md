# Research: Wireguard VPN on OPNsense via API

**Feature**: 058-wireguard-management-vpn

## Decision: OPNsense REST API for Wireguard
The `os-wireguard` plugin provides a robust REST API under the `wireguard` module. 

- **Rationale**: Consistent with existing `network-deploy.yml` which already uses `firewall` and `unbound` API modules.
- **Alternatives Considered**: 
  - Manual configuration: Rejected (violates Principle I).
  - SSH/CLI commands: Rejected (less robust than REST API).

## Decision: Key Management via Ansible
Private keys will be generated locally on the management machine (or OPNsense) and stored in `group_vars/all.yml`. 

- **Rationale**: Follows Principle IV (Secrets Hygiene). Keys remain out of Git.
- **Alternatives Considered**: 
  - Let OPNsense generate keys: Difficult to retrieve the private key for the laptop client via API.

## Decision: Subnet Allocation
A new subnet `10.1.254.0/24` will be used for the VPN tunnel.

- **Rationale**: High-range IP avoids conflict with existing `10.1.1.0/24` (Mgmt) and `10.1.20.0/24` (Cluster).

## Decision: Firewall Rules
Rules will be added to the `Wireguard` group interface in OPNsense.

- **Rationale**: OPNsense automatically creates an interface group for Wireguard, making rule management simpler than per-instance interfaces.
