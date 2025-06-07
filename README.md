# Vanlab Deploy

A project for deploying the Vanlab cluster and services using Ansible and Helm.

Current configuration for the Vanlab cluster:

4x Pi5 8GB w/ PoE + M2 Hat w/ 2TB drives

## Known Issue

Current playbook does not allow agents to join the cluster proprely. Manual steps:

1. Stop the K3S agent if running
   - `sudo systemctl stop k3s-agent`
1. Uninstall K3S
   - `sudo k3s-killall.sh`
   - `sudo rm -rf /var/lib/rancher/k3s /var/lib/kubelet /etc/rancher/k3s`
1. Reboot
   - `sudo reboot now`
1. Run install and join command (replacing `[MASTER_IP]` and `[JOIN_TOKEN]`
   - `curl -sfL https://get.k3s.io | K3S_URL=https://[MASTER_IP]:6443 K3S_TOKEN=[JOIN_TOKEN] sh -`

## Todo

[ ] Fix worker node joining in playbook
[ ] Migrate to Pi ComputeBlades with AI expansion board
