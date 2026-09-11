# ==============================================================================
# security_groups.tf
# Bastion accepts SSH only from YOUR IP. Master/worker accept SSH ONLY from
# the bastion's security group - never directly from the internet, and not
# even from other things inside the VPC unless explicitly allowed here.
# ==============================================================================

resource "aws_security_group" "bastion" {
  name        = "${var.cluster_name}-bastion-sg"
  description = "Allows SSH from the operator IP only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH from allowed operator IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.cluster_name}-bastion-sg" }
}

resource "aws_security_group" "node" {
  name        = "${var.cluster_name}-node-sg"
  description = "Master/worker - SSH only from bastion, k8s ports only from other nodes"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "SSH from bastion only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # Kubernetes control-plane + kubelet + NodePort ranges, restricted to
  # traffic between cluster nodes themselves (self-referencing rule).
  ingress {
    description = "Kubernetes API server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    self        = true
  }
  ingress {
    description = "Kubernetes API server access for bastion"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }
  ingress {
    description = "bgp_worker_to_worker"
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    self        = true
  }
  ingress {
    description = "etcd"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "kubelet / scheduler / controller-manager"
    from_port   = 10250
    to_port     = 10252
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "NodePort services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Calico BGP + VXLAN pod networking"
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.cluster_name}-node-sg" }
}
