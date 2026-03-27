# Vanlab Deploy

A project for deploying the Vanlab cluster and services using Ansible and Helm.

Current configuration for the Vanlab cluster:

- 4x Pi5 8GB w/ PoE + M2 Hat w/ 2TB drives

## Deploy
Deploy the K3s cluster:

```
ansible-playbook -i hosts.ini k3s-deploy.yml
```
Deploy services to cluster:
```
ansible-playbook -i hosts.ini services-deploy.yml
```
## Utilities
Check NVMe drive presence, capacity, and S.M.A.R.T. health across all nodes:
```
ansible-playbook -i hosts.ini disk-health.yml
```
Exits with code `0` if all drives are healthy, `2` if any node has a CRITICAL, MISSING, or UNREACHABLE status.

## Known Issue
Current playbook does not allow agents to join the cluster proprely. Manual steps:
1. Stop the K3S agent if running
   1. `sudo systemctl stop k3s-agent`
1. Uninstall K3S
   1. `sudo k3s-killall.sh`
   1. `sudo rm -rf /var/lib/rancher/k3s /var/lib/kubelet /etc/rancher/k3s`
1. Reboot
   1. `sudo reboot now`
1. Run install and join command (replacing `[MASTER_IP]` and `[JOIN_TOKEN]`
   1. `curl -sfL https://get.k3s.io | K3S_URL=https://[MASTER_IP]:6443 K3S_TOKEN=[JOIN_TOKEN] sh -`
## Todo
- [ ] Fix worker node joining in playbook
- [ ] Migrate to Pi ComputeBlades with AI expansion board
