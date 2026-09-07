# ==============================================================================
# keys.tf
# Terraform generates BOTH SSH keypairs itself - Jenkins never needs to hold
# or inject an SSH private key. The private keys live only in Terraform state
# (which should be stored in an encrypted backend, e.g. S3 + KMS - see README)
# and are exposed via sensitive outputs when a human needs to SSH in manually.
# ==============================================================================

resource "tls_private_key" "bastion" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_private_key" "node" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion" {
  key_name   = "${var.cluster_name}-bastion-key"
  public_key = tls_private_key.bastion.public_key_openssh
}

resource "aws_key_pair" "node" {
  key_name   = "${var.cluster_name}-node-key"
  public_key = tls_private_key.node.public_key_openssh
}
