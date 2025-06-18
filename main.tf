resource "aws_instance" "rhel_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = data.terraform_remote_state.aws_dev_vpc.outputs.vpc_public_subnets[0]
  key_name      = var.aws_key_pair_name
  tags          = var.ec2_tags
  vpc_security_group_ids = [data.terraform_remote_state.aws_dev_vpc.outputs.security_group-ssh_http_https_allowed]
  iam_instance_profile = "tfstacks-profile"
}

resource "aws_ec2_instance_state" "rhel_instance_state" {
  instance_id = aws_instance.rhel_instance.id
  state       = "running"
}

#resource "aws_eip" "instance-eip" {
#  instance = aws_instance.rhel_instance.id
#  vpc      = true
#}

locals {
  vm_names = {
    hostname = "rhel9-vm" # Map with a single key-value pair
  }
}

resource "null_resource" "wait_for_status_checks" {
  provisioner "local-exec" {
    command = <<EOT
      INSTANCE_ID=${aws_instance.rhel_instance.id}
      REGION="${var.aws_region}"

      echo "Waiting for EC2 status checks to pass for $INSTANCE_ID in $REGION..."
      while true; do
        OUTPUT=$(aws ec2 describe-instance-status --instance-id $INSTANCE_ID --region $REGION --output json)
        INSTANCE_STATUS=$(echo $OUTPUT | jq -r '.InstanceStatuses[0].InstanceStatus.Status')
        SYSTEM_STATUS=$(echo $OUTPUT | jq -r '.InstanceStatuses[0].SystemStatus.Status')

        if [ "$INSTANCE_STATUS" = "ok" ] && [ "$SYSTEM_STATUS" = "ok" ]; then
          echo "EC2 instance passed 2/2 status checks."
          break
        else
          echo "Waiting... Instance: $INSTANCE_STATUS, System: $SYSTEM_STATUS"
          sleep 10
        fi
      done
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [aws_ec2_instance_state.rhel_instance_state]
}


resource "aap_inventory" "vm_inventory" {
  name        = "Better Together Demo - ${var.TFC_WORKSPACE_ID}"
  description = "Inventory for VMs built with HCP Terraform and managed by AAP"
  variables   = jsonencode({})
#  lifecycle {
#    prevent_destroy = true
#  }
  depends_on  = [null_resource.wait_for_status_checks]
}

resource "aap_host" "vm_host" {
  inventory_id = aap_inventory.vm_inventory.id
  name         = local.vm_names.hostname # Fixed: Use the string value from the map

  variables = jsonencode({
    ansible_host = aws_instance.rhel_instance.public_ip
  })
}

resource "aap_job" "vm_demo_job" {
  job_template_id = var.job_template_id
  inventory_id    = aap_inventory.vm_inventory.id
  extra_vars      = jsonencode({})
  triggers        = local.vm_names
  depends_on      = [aap_inventory.vm_inventory]
}