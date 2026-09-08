#!/bin/bash
# ==============================================================================
# bastion-kubectl.sh
# Installs the kubectl CLIENT ONLY on the bastion - no containerd, kubelet,
# or kubeadm (this host is never a cluster node). Lets you run kubectl
# directly on the bastion against the kubeconfig copied there during the
# master bootstrap, instead of having to SSH onward to the master every time.
#
# NOTE: the version below (v1.37) must match the same minor version used in
# scripts/common.sh - see the coupling warning in variables.tf.
# ==============================================================================
set -euo pipefail

echo ">>> [bastion-kubectl.sh] Installing kubectl client"
sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.37/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -y
sudo apt-get install -y kubectl
sudo apt-mark hold kubectl

echo ">>> [bastion-kubectl.sh] kubectl installed:"
kubectl version --client
