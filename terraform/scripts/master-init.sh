#!/bin/bash
# ==============================================================================
# master-init.sh
# Runs ONLY on the master node, AFTER common.sh.
# Initializes the control plane and writes a ready-to-use join command
# to /tmp/kubeadm_join_cmd.sh so Terraform can pull it down for the workers.
# ==============================================================================
set -euo pipefail

POD_CIDR="$1"   # passed in from Terraform, e.g. 192.168.0.0/16
CALICO_VERSION="v3.32.2"
KCFG="$HOME/.kube/config"

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
# ---------------------------------------------------------------------------
# 1. CRDs + Operator (official install order per Calico docs)
# ---------------------------------------------------------------------------
kubectl --kubeconfig="$KCFG" create -f \
  "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/v1_crd_projectcalico_org.yaml"

kubectl --kubeconfig="$KCFG" create -f \
  "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"

until kubectl --kubeconfig="$KCFG" get crd installations.operator.tigera.io >/dev/null 2>&1; do
  sleep 5
done

# ---------------------------------------------------------------------------
# 2. Download custom-resources.yaml, patch the pod CIDR, apply
# ---------------------------------------------------------------------------
curl -fsSL -O "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/custom-resources.yaml"

sed -i "s|cidr: 192.168.0.0/16|cidr: ${POD_NETWORK_CIDR}|" custom-resources.yaml

if ! grep -q "cidr: ${POD_NETWORK_CIDR}" custom-resources.yaml; then
  echo "ERROR: failed to patch pod CIDR into custom-resources.yaml - upstream file format may have changed."
  cat custom-resources.yaml
  exit 1
fi

# Docs recommend 'create' here too - the CRD bundle from step 1 is large
# enough that 'apply' can exceed the last-applied-configuration size limit.
kubectl --kubeconfig="$KCFG" create -f custom-resources.yaml

# ---------------------------------------------------------------------------
# 3. Wait for Calico to actually come up before moving on
# ---------------------------------------------------------------------------
kubectl --kubeconfig="$KCFG" wait --for=condition=Available --timeout=300s tigerastatus/calico 2>/dev/null || \
kubectl --kubeconfig="$KCFG" rollout status daemonset/calico-node -n calico-system --timeout=300s

echo ">>> [master-init.sh] Generating the worker join command"
JOIN_CMD=$(kubeadm token create --print-join-command)
echo "sudo ${JOIN_CMD}" > /tmp/kubeadm_join_cmd.sh
chmod +x /tmp/kubeadm_join_cmd.sh

echo ">>> [master-init.sh] Master is ready. Join command saved to /tmp/kubeadm_join_cmd.sh"
