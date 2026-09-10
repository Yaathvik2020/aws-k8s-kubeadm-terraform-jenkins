# ==============================================================================
# main.tf
# Terraform connects ONLY to the bastion. The bastion then relays ssh/scp
# onward to master/worker over their PRIVATE IPs - Terraform never talks to
# the nodes directly, matching: Jenkins -> Terraform -> Bastion -> Nodes.
# ==============================================================================

locals {
  bastion_connection = {
    type        = "ssh"
    host        = aws_instance.bastion.public_ip
    user        = var.ssh_user
    private_key = tls_private_key.bastion.private_key_pem
  }
}

# ------------------------------------------------------------------------------
# Stage 1: upload the node private key + bootstrap scripts onto the bastion.
# Uploaded fresh each run; wiped again in the cleanup step below.
# ------------------------------------------------------------------------------
resource "null_resource" "prep_bastion" {
  depends_on = [null_resource.wait_for_bastion, aws_instance.master, null_resource.setup_kubectl_on_bastion, aws_instance.worker]

  connection {
    type        = "ssh"
    host        = aws_instance.bastion.public_ip
    user        = var.ssh_user
    private_key = tls_private_key.bastion.private_key_pem
  }

  provisioner "file" {
    content     = tls_private_key.node.private_key_pem
    destination = "/home/${var.ssh_user}/node_key"
  }
  
  provisioner "file" {
    source      = "${path.module}/scripts/common.sh"
    destination = "/home/${var.ssh_user}/common.sh"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/master-init.sh"
    destination = "/home/${var.ssh_user}/master-init.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 600 /home/${var.ssh_user}/node_key",
      "chmod +x /home/${var.ssh_user}/common.sh /home/${var.ssh_user}/master-init.sh",
    ]
  }
}

# ------------------------------------------------------------------------------
# Stage 2: bastion relays the bootstrap to the MASTER over its private IP.
# A retry loop covers the case where the EC2 instance is still finishing
# boot when the bastion first tries to reach it.
# ------------------------------------------------------------------------------
resource "null_resource" "bootstrap_master_via_bastion" {
  depends_on = [null_resource.prep_bastion]

  connection {
    type        = "ssh"
    host        = aws_instance.bastion.public_ip
    user        = var.ssh_user
    private_key = tls_private_key.bastion.private_key_pem
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
        for i in $(seq 1 20); do
          ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i ~/node_key \
            ${var.ssh_user}@${aws_instance.master.private_ip} "echo ok" && break
          echo "Waiting for master SSH... ($i/20)"; sleep 10
        done
      EOT
      ,
      "scp -o StrictHostKeyChecking=no -i ~/node_key ~/common.sh ~/master-init.sh ${var.ssh_user}@${aws_instance.master.private_ip}:/tmp/",
      "ssh -o StrictHostKeyChecking=no -i ~/node_key ${var.ssh_user}@${aws_instance.master.private_ip} 'chmod +x /tmp/common.sh /tmp/master-init.sh && /tmp/common.sh && /tmp/master-init.sh ${var.pod_network_cidr}'",
      "scp -o StrictHostKeyChecking=no -i ~/node_key ${var.ssh_user}@${aws_instance.master.private_ip}:/tmp/kubeadm_join_cmd.sh ~/kubeadm_join_cmd.sh",
      "scp -o StrictHostKeyChecking=no -i ~/node_key ${var.ssh_user}@${aws_instance.master.private_ip}:~/.kube/config ~/kubeconfig",
    ]
  }
}
# ------------------------------------------------------------------------------
# Stage 3: bastion setup_kubectl_on_bastion
# ------------------------------------------------------------------------------
resource "null_resource" "setup_kubectl_on_bastion" {
  depends_on = [null_resource.bootstrap_master_via_bastion]

  connection {
    type        = "ssh"
    host        = aws_instance.bastion.public_ip
    user        = var.ssh_user
    private_key = tls_private_key.bastion.private_key_pem
  }

  provisioner "remote-exec" {
    inline = [
      # kubeconfig was already pulled from master to the bastion's ~/kubeconfig
      # during bootstrap_master_via_bastion — set it up as the default config
      "mkdir -p ~/.kube",
      "cp ~/kubeconfig ~/.kube/config",
      "chmod 600 ~/.kube/config",

      # sanity check
      "kubectl get nodes -o wide"
    ]
  }
}
# ------------------------------------------------------------------------------
# Stage 4: same pattern per WORKER.
# ------------------------------------------------------------------------------
resource "null_resource" "bootstrap_worker_via_bastion" {
  count      = var.worker_count
  depends_on = [null_resource.bootstrap_master_via_bastion]

  connection {
    type        = "ssh"
    host        = aws_instance.bastion.public_ip
    user        = var.ssh_user
    private_key = tls_private_key.bastion.private_key_pem
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
        for i in $(seq 1 20); do
          ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i ~/node_key \
            ${var.ssh_user}@${aws_instance.worker[count.index].private_ip} "echo ok" && break
          echo "Waiting for worker SSH... ($i/20)"; sleep 10
        done
      EOT
      ,
      "scp -o StrictHostKeyChecking=no -i ~/node_key ~/common.sh ${var.ssh_user}@${aws_instance.worker[count.index].private_ip}:/tmp/",
      "ssh -o StrictHostKeyChecking=no -i ~/node_key ${var.ssh_user}@${aws_instance.worker[count.index].private_ip} 'chmod +x /tmp/common.sh && /tmp/common.sh'",
      "scp -o StrictHostKeyChecking=no -i ~/node_key ~/kubeadm_join_cmd.sh ${var.ssh_user}@${aws_instance.worker[count.index].private_ip}:/tmp/kubeadm_join_cmd.sh",
      "ssh -o StrictHostKeyChecking=no -i ~/node_key ${var.ssh_user}@${aws_instance.worker[count.index].private_ip} 'chmod +x /tmp/kubeadm_join_cmd.sh && /tmp/kubeadm_join_cmd.sh'",
    ]
  }
}

# --------------------------------------------------------------------------------------------------------------------------------
# Stage 5: wipe the node key off the bastion once bootstrap is complete. skip the step  node key  needs to connect master via ssh
# --------------------------------------------------------------------------------------------------------------------------------
# resource "null_resource" "cleanup_bastion_key" {
#  depends_on = [null_resource.bootstrap_worker_via_bastion]

# connection {
#    type        = "ssh"
#   host        = aws_instance.bastion.public_ip
#    user        = var.ssh_user
#    private_key = tls_private_key.bastion.private_key_pem
 # }

  #provisioner "remote-exec" {
   # inline = ["shred -u ~/node_key || rm -f ~/node_key"]
  #}
#}
