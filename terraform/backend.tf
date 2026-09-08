# ==============================================================================
# backend.tf.example
# IMPORTANT: Terraform state for this project contains the generated SSH
# PRIVATE KEYS in plaintext (see keys.tf outputs). Local state files are NOT
# safe for this - use an encrypted remote backend. Copy this to backend.tf
# and fill in a bucket/table you've created beforehand.
# ==============================================================================

terraform {
  backend "s3" {
    bucket         = "ksys-k8s-terraform-state-bucket"
    key            = "k8s-kubeadm/terraform.tfstate"
    region         = "ap-south-1"
	use_lockfile   = true
    encrypt        = true                    # SSE-S3 encryption at rest
    #dynamodb_table = "your-terraform-lock-table"  # state locking, prevents concurrent applies
  }
}
