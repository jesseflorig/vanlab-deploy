# Contract: OPNsense Wireguard API Interaction

**Feature**: 058-wireguard-management-vpn

## Overview
This contract defines how Ansible interacts with the OPNsense `os-wireguard` REST API to provision the VPN.

## Endpoints

### 1. Server Configuration
- **Path**: `/api/wireguard/server/addServer` (POST) or `setServer/<uuid>` (POST)
- **Payload**:
  ```json
  {
    "server": {
      "enabled": "1",
      "name": "fleet1_vpn",
      "listenport": "51820",
      "tunneladdress": "10.1.254.1/24",
      "privkey": "{{ wireguard_server_private_key }}"
    }
  }
  ```

### 2. Client (Peer) Configuration
- **Path**: `/api/wireguard/client/addClient` (POST) or `setClient/<uuid>` (POST)
- **Payload**:
  ```json
  {
    "client": {
      "enabled": "1",
      "name": "management_laptop",
      "pubkey": "{{ wireguard_client_public_key }}",
      "tunneladdress": "10.1.254.2/32"
    }
  }
  ```

### 3. Service Control
- **Path**: `/api/wireguard/service/reconfigure` (POST)
- **Payload**: `{}`
- **Purpose**: Applies all pending changes to the Wireguard service.

## Validation Rules
- **Idempotency**: Search for existing servers/clients by `name` before creating.
- **Errors**: Fail if the `os-wireguard` plugin is not found (status 404).
