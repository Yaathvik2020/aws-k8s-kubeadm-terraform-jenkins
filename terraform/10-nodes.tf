# ==============================================================================
# nodes.tf
# Master and worker EC2 instances - private subnet, NO public IP. Only
# reachable from the bastion (enforced by security_groups.tf), and only
# have outbound internet via the NAT Gateway.
# ==============================================================================

resource "aws_instance" "master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.node_instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.node.id]
  key_name               = aws_key_pair.node.key_name
  iam_instance_profile   = aws_iam_instance_profile.k8s-kubeadm-aws-alb-iam-profile.name

  tags = { Name = "${var.cluster_name}-master" }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }
 depends_on = [                              # ← ADD THIS, right here, still inside the { } of aws_instance.master
    aws_nat_gateway.this,
    aws_route.private_nat,
    aws_route_table_association.private
  ]
}

resource "aws_instance" "worker" {
  count                  = var.worker_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.node_instance_type
  subnet_id              = aws_subnet.private[1].id
  vpc_security_group_ids = [aws_security_group.node.id]
  key_name               = aws_key_pair.node.key_name
  iam_instance_profile   = aws_iam_instance_profile.k8s-kubeadm-aws-alb-iam-profile.name
  tags = { Name = "${var.cluster_name}-worker-${count.index + 1}" }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }
 depends_on = [                              # ← ADD THIS, right here, still inside the { } of aws_instance.master
    aws_nat_gateway.this,
    aws_route.private_nat,
    aws_route_table_association.private
  ]
}
