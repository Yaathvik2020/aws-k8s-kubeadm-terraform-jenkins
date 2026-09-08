# ==============================================================================
# variables.tf
# ==============================================================================

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "Prefix used to name/tag every resource this project creates"
  type        = string
  default     = "k8s-kubeadm"
}

# ------------------------------------------------------------------------------
# Networking
# ------------------------------------------------------------------------------
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the two public subnets (bastion + NAT)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the two private subnets (master + workers)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}
variable "azs" {
  description = "Availability zones to spread subnets across (must have exactly 2)"
  type        = list(string)
  default     = []
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway (cheaper) instead of one per AZ (HA)"
  type        = bool
  default     = true
}

variable "allowed_ssh_cidr" {
  description = "YOUR IP (as x.x.x.x/32) allowed to SSH into the bastion. Leave unset (null) to auto-detect the IP of whoever runs 'terraform apply'."
  type        = string
  default     = null
}

# ------------------------------------------------------------------------------
# Instances
# ------------------------------------------------------------------------------
variable "bastion_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "node_instance_type" {
  description = "Instance type for master AND worker nodes"
  type        = string
  default     = "t3.medium" # kubeadm's minimum is 2 vCPU / 2GB - t3.medium covers this comfortably
}

variable "worker_count" {
  description = "Number of worker nodes to create"
  type        = number
  default     = 2
}

variable "root_volume_size" {
  description = "Root EBS volume size (GB) for master/worker nodes"
  type        = number
  default     = 30
}

variable "ssh_user" {
  description = "Default SSH user for the chosen AMI (Ubuntu AMIs use 'ubuntu')"
  type        = string
  default     = "ubuntu"
}

# ------------------------------------------------------------------------------
# Kubernetes
# ------------------------------------------------------------------------------
# NOTE: the minor version here (e.g. 1.37) must match the repo path
# hardcoded in scripts/common.sh ("core:/stable:/v1.37/deb/"). Bumping
# just this default without updating common.sh will NOT install the
# new version - apt will still pull from the old minor-version repo.
variable "kubernetes_version" {
  type    = string
  default = "1.37.0-1.1"
}

variable "pod_network_cidr" {
  type    = string
  default = "192.168.0.0/16"
}
