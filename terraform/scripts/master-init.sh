#!/bin/bash
# ==============================================================================
# master-init.sh
# Runs ONLY on the master node, AFTER common.sh.
# Initializes the control plane and writes a ready-to-use join command
# to /tmp/kubeadm_join_cmd.sh so Terraform can pull it down for the workers.
# ==============================================================================
set -euo pipefail

POD_CIDR="$1"   # passed in from Terraform, e.g. 192.168.0.0/16

echo ">>> [master-init.sh] Checking if cluster is already initialized"
if [ -f /etc/kubernetes/admin.conf ]; then
  echo "Cluster already initialized, skipping kubeadm init."
else
  echo ">>> [master-init.sh] Running kubeadm init"
  sudo kubeadm init --pod-network-cidr="${POD_CIDR}" --ignore-preflight-errors=NumCPU
fi

echo ">>> [master-init.sh] Setting up kubeconfig for the ssh user"
mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u)":"$(id -g)" "$HOME/.kube/config"

echo ">>> [master-init.sh] Installing Calico CNI (pod networking)"
kubectl --kubeconfig="$HOME/.kube/config" apply -f \
  https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

echo ">>> [master-init.sh] Generating the worker join command"
JOIN_CMD=$(kubeadm token create --print-join-command)
echo "sudo ${JOIN_CMD}" > /tmp/kubeadm_join_cmd.sh
chmod +x /tmp/kubeadm_join_cmd.sh

echo ">>> [master-init.sh] Master is ready. Join command saved to /tmp/kubeadm_join_cmd.sh"
