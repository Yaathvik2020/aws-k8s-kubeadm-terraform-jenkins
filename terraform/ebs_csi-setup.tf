
# ---------------------------------------------------------------------------
# Installs the EBS CSI driver and the ebs-sc StorageClass, run on the
# bastion automatically as part of terraform apply - same pattern as the
# ALB controller install.
# ---------------------------------------------------------------------------
resource "null_resource" "install_ebs_csi_driver" {
 depends_on = [
    null_resource.setup_kubectl_on_bastion,
    aws_iam_role_policy_attachment.ebs_csi,
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
    source      = "${path.module}/k8s-manifests/ebs-storageclass.yaml"
    destination = "/tmp/ebs-storageclass.yaml"
  }

  provisioner "remote-exec" {
    inline = concat(
      [
        # CSI driver itself
        "kubectl apply -k \"github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.35\"",

        # Wait for it to actually be up before applying the StorageClass -
        # not strictly required (the StorageClass object can exist before
        # the driver does), but catches install failures immediately rather
        # than surfacing later as a mysteriously-stuck PVC.
        "kubectl -n kube-system rollout status deployment/ebs-csi-controller --timeout=180s",

        # The StorageClass
        "kubectl apply -f /tmp/ebs-storageclass.yaml",
      ],
      var.ebs_sc_default ? [
        # Set as cluster default so PVCs don't need storageClassName set.
        # Also un-defaults any other StorageClass first - only one default
        # is allowed at a time, and leaving a stale one marked default
        # causes "multiple default StorageClasses" errors on PVC creation.
        "for sc in $(kubectl get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\\.kubernetes\\.io/is-default-class==\"true\")].metadata.name}'); do kubectl patch storageclass \"$sc\" -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}'; done",
        "kubectl patch storageclass ebs-sc -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}'",
      ] : [],
      [
        # Sanity check
        "kubectl get storageclass",
      ]
    )
  }
}
