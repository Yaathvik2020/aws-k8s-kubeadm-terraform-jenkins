output "allowed_ssh_cidr" {
  description = "The CIDR actually applied to the bastion's security group (auto-detected unless overridden)"
  value       = local.ssh_cidr
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "master_private_ip" {
  value = aws_instance.master.private_ip
}

output "worker_private_ips" {
  value = aws_instance.worker[*].private_ip
}

output "bastion_private_key_pem" {
  description = "Retrieve with: terraform output -raw bastion_private_key_pem > bastion_key.pem"
  value       = tls_private_key.bastion.private_key_pem
  sensitive   = true
}

output "node_private_key_pem" {
  description = "Retrieve with: terraform output -raw node_private_key_pem > node_key.pem"
  value       = tls_private_key.node.private_key_pem
  sensitive   = true
}

output "next_steps" {
  value = <<-EOT
    Cluster bootstrap finished, entirely on AWS, relayed through the bastion.
    A copy of the kubeconfig is already sitting on the bastion at ~/kubeconfig -
    no need to reach the master directly to grab it.

    To manage the cluster from your own machine:
      terraform output -raw bastion_private_key_pem > bastion_key.pem && chmod 600 bastion_key.pem

      scp -i bastion_key.pem ${var.ssh_user}@${aws_instance.bastion.public_ip}:~/kubeconfig ./kubeconfig
      export KUBECONFIG=./kubeconfig
      kubectl get nodes
  EOT
}
