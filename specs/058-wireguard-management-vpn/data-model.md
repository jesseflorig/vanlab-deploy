# Data Model: Wireguard VPN

**Feature**: 058-wireguard-management-vpn

## Entities

### Wireguard Server (Local)
- **Enabled**: boolean (1/0)
- **Name**: "fleet1_vpn"
- **Instance**: 0
- **ListenPort**: 51820
- **Address**: 10.1.254.1/24
- **PrivateKey**: secret (from group_vars)
- **PublicKey**: derived or provided

### Wireguard Client (Peer)
- **Enabled**: boolean (1/0)
- **Name**: "management_laptop"
- **PublicKey**: string (from group_vars)
- **AllowedIPs**: 10.1.254.2/32
- **ServerAddress**: 10.1.254.1
- **ServerPort**: 51820

## Relationships
- **Server** has 0..N **Peers**
- **Firewall Rule** references **Wireguard Interface Group**
- **Unbound** provides DNS for **VPN Subnet**
