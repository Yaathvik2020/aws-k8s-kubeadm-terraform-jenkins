# ==============================================================================
# bastion.tf
# The bastion EC2 instance - the only machine in this whole setup that gets
# a public IP. Terraform connects to it directly; it then relays commands
# onward to master/worker (see main.tf).
# ==============================================================================

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = aws_key_pair.bastion.key_name
  associate_public_ip_address = true

  tags = { Name = "${var.cluster_name}-bastion" }
 depends_on = [                              # ← ADD THIS, right here, still inside the { } of aws_instance.master
    aws_internet_gateway.this,
    aws_route.public_internet,
    aws_route_table_association.public
  ]
}

# Waits until cloud-init/SSH is actually ready - "instance running" and
# "SSH accepting connections" are not the same moment.
resource "null_resource" "wait_for_bastion" {
  depends_on = [aws_instance.bastion]

  connection {
    type        = "ssh"
    host        = aws_instance.bastion.public_ip
    user        = var.ssh_user
    private_key = tls_private_key.bastion.private_key_pem
    timeout     = "5m"
  }
 
   provisioner "file" {
    source      = "${path.module}/scripts/bastion-kubectl.sh"
    destination = "/home/${var.ssh_user}/bastion-kubectl.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/${var.ssh_user}/bastion-kubectl.sh && /home/${var.ssh_user}/bastion-kubectl.sh",   
    ]
  }
}
