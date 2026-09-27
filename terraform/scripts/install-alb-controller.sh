#!/bin/bash
# Run this FROM THE BASTION after `terraform apply` has completed and
# kubectl is already working (kubectl get nodes should show master+workers).
set -euxo pipefail

CLUSTER_NAME="${1:?Usage: install-alb-controller.sh <cluster_name> <aws_region> <vpc_id>}"
AWS_REGION="${2:?}"
VPC_ID="${3:?}"

# ---------------------------------------------------------------------------
# 1. Install Helm (not present on the bastion by default)
# ---------------------------------------------------------------------------
if ! command -v helm >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
helm version

# ---------------------------------------------------------------------------
# 2. Install the controller's CRDs. Some Helm chart versions bundle these
# automatically; applying explicitly first is idempotent and safe either
# way, and avoids "no matches for kind TargetGroupBinding" errors if the
# chart version in use doesn't include them.
# ---------------------------------------------------------------------------
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"

# ---------------------------------------------------------------------------
# 3. Install the AWS Load Balancer Controller via Helm
#
# No IRSA/OIDC on this cluster, so no serviceAccount.annotations pointing
# at an IAM role ARN - the controller pod just inherits whatever IAM role
# is on the WORKER NODE it happens to be scheduled on (see
# iam-alb-controller.tf - the instance profile attached to workers).
# ---------------------------------------------------------------------------
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$AWS_REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller

# ---------------------------------------------------------------------------
# 4. Wait for it to come up
# ---------------------------------------------------------------------------
kubectl -n kube-system rollout status deployment/aws-load-balancer-controller --timeout=180s
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-load-balancer-controller

echo ">>> AWS Load Balancer Controller installed."
echo ">>> Next: point Istio's ingress gateway Service at it - see expose-istio-nlb.sh"
