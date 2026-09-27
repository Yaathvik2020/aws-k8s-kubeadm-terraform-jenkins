# ---------------------------------------------------------------------------
# EC2 instance IAM role for the AWS Load Balancer Controller.
#
# Unlike the static NLB in nlb.tf (which Terraform itself creates, needing
# no instance role - see iam-nlb-permissions.tf), THIS controller runs as a
# POD inside the cluster and calls the ELB API on its own, on your behalf,
# whenever it sees a Service of type LoadBalancer or an Ingress. On EKS this
# uses IRSA (per-pod IAM via OIDC); this cluster has no OIDC provider, so the
# controller falls back to the EC2 INSTANCE role of whichever node it's
# scheduled on. Every worker gets this role attached (the master is left out
# by default - the controller isn't scheduled there in a normal setup).
# ---------------------------------------------------------------------------
# ---  already cutsom plicy  and  alb role set up has done iam.tf ---*/
/* ---
 data "http" "alb_controller_iam_policy" {
   url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.10.0/docs/install/iam_policy.json"
 }

 resource "aws_iam_role" "alb_controller" {
  name = "${var.cluster_name}-alb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "alb_controller" {
  name   = "${var.cluster_name}-alb-controller-policy"
  policy = data.http.alb_controller_iam_policy.response_body
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

resource "aws_iam_instance_profile" "alb_controller" {
  name = "${var.cluster_name}-alb-controller-profile"
  role = aws_iam_role.alb_controller.name
}
 --- */
# ---------------------------------------------------------------------------
# Runs install-alb-controller.sh ON THE BASTION automatically - installs
# Helm, the controller's CRDs, and the controller itself via Helm. Depends
# on the bastion actually having a working kubeconfig (main.tf) and the
# nodes having their providerID set (main.tf) so the controller can
# correctly map Nodes to EC2 instances once it starts.
# ---------------------------------------------------------------------------
resource "null_resource" "install_alb_controller" {
  depends_on = [
    null_resource.setup_kubectl_on_bastion,
    null_resource.patch_node_provider_ids,
    aws_iam_role_policy_attachment.aws-lb-policy,
  ]

  triggers = {
    cluster_name = var.cluster_name
  }

  connection {
    type        = "ssh"
    host        = aws_instance.bastion.public_ip
    user        = "ubuntu"
    private_key = tls_private_key.bastion.private_key_pem
  }

  provisioner "file" {
    source      = "${path.module}/scripts/install-alb-controller.sh"
    destination = "/tmp/install-alb-controller.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install-alb-controller.sh",
      "/tmp/install-alb-controller.sh \"${var.cluster_name}\" \"${var.aws_region}\" \"${aws_vpc.this.id}\"",
    ]
  }
}
