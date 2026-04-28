# Quickstart: Wireguard VPN Management Access

## Prerequisites
1. OPNsense `os-wireguard` plugin installed.
2. Management laptop with Wireguard client installed.
3. Private/Public keys generated for both server and laptop.
4. Public keys added to `group_vars/all.yml` (see `example.all.yml`).

## Apply Configuration
Run the network-deploy playbook:
```bash
ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml
```

## Client Setup
1. Create a file `fleet1.conf` on your laptop:
```ini
[Interface]
PrivateKey = <LAPTOP_PRIVATE_KEY>
Address = 10.1.254.2/32
DNS = 10.1.1.1

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
Endpoint = <OPNSENSE_WAN_IP>:51820
AllowedIPs = 10.1.1.0/24, 10.1.20.0/24, 10.1.254.0/24
```
2. Import the config into your Wireguard client.
3. Activate the tunnel.

## Validation
1. **Ping Test**: `ping 10.1.1.1` should succeed.
2. **DNS Test**: `dig opnsense.fleet1.lan +short` should return `10.1.1.1`.
3. **Web UI Test**: Open `https://opnsense.fleet1.lan` in a browser.
