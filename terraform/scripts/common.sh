#!/bin/bash
# ==============================================================================
# common.sh
# Runs on EVERY node (master AND workers).
# Installs everything kubeadm needs before you can init or join a cluster.
# ==============================================================================
set -euo pipefail

echo ">>> [common.sh] Disabling swap (kubelet refuses to start with swap on)"
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

echo ">>> [common.sh] Loading required kernel modules"
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

echo ">>> [common.sh] Setting required sysctl params"
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

echo ">>> [common.sh] Installing containerd"
sudo apt-get update -y
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
# Use systemd as the cgroup driver (kubeadm requirement)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

echo ">>> [common.sh] Adding Kubernetes apt repo"
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.37/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

echo ">>> [common.sh] Installing kubeadm, kubelet, kubectl"
sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo systemctl enable kubelet

echo ">>> [common.sh] Done. Node is ready for kubeadm init/join."
