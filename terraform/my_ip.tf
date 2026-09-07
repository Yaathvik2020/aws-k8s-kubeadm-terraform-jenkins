# ==============================================================================
# my_ip.tf
# Auto-detects the public IP of whoever/whatever runs "terraform apply" (your
# laptop, or the Jenkins agent) and uses it for allowed_ssh_cidr - no more
# manually running curl and editing tfvars every time it changes.
#
# If you'd rather set it explicitly (e.g. to allow a DIFFERENT IP than the
# one running Terraform), just set allowed_ssh_cidr in terraform.tfvars -
# an explicit value always overrides auto-detection.
# ==============================================================================

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  detected_cidr = "${trimspace(data.http.my_ip.response_body)}/32"
  ssh_cidr      = coalesce(var.allowed_ssh_cidr, local.detected_cidr)
}
