variable "aws_region" {
  type    = string
  default = "ap-southeast-2"
}

variable "ami_id" {
  type        = string
  default     = "ami-0df3f3adca5bd27bd" # RHEL9 - 2025-05-29
  description = "The id of the machine image (AMI) to use for the server."
}

variable "instance_type" {
  type    = string
  default = "t2.micro" # change to t2.small (t2.micro) or larger for production use
}

variable "aws_key_pair_name" {
  type    = string
  default = "djoo-demo-ec2-keypair"
}

variable "ec2_tags" {
  description = "Tags for EC2 instance"
  type        = map(string)
  default = {
    Terraform   = "true"
    Environment = "Dev"
    Owner       = "djoo"
    Name        = "tf-aws-dev-ec2-RHEL9-vault-agent"
    Test_Tag    = "This is a demo for Do Cloud Right Melbourne"
  }
}

variable "TFC_WORKSPACE_ID" {
  type        = string
  description = "Terraform Cloud workspace ID"
}

# Bump this value (e.g. 1 -> 2) and apply to fire the chrony_timesync action via
# the after_update trigger on terraform_data.vm_provisioned. Demo handle only.
variable "demo_chrony_trigger" {
  type        = number
  default     = 1
  description = "Bump to fire the chrony_timesync after_update action."
}

# Used by aws_instance user_data to fetch the Vault SSH CA public key at
# first-boot and configure /etc/ssh to trust it for the `aap` user.
variable "vault_addr" {
  type        = string
  description = "HCP Vault address (used by EC2 user_data to fetch the SSH CA public key)."
  default     = "https://djoo-test-vault-public-vault-a40e8748.a3bc1cae.z1.hashicorp.cloud:8200"
}

variable "vault_namespace" {
  type        = string
  description = "Vault namespace for the ssh/public_key endpoint."
  default     = "admin"
}

variable "aap_endpoint" {
  type        = string
  description = "AAP API endpoint"
}

variable "aap_token" {
  type        = string
  description = "AAP API token"
  sensitive   = true
}

variable "aap_host" {
  type        = string
  description = "AAP API host (e.g., https://aap.example.com)"
}

variable "aap_username" {
  type        = string
  description = "AAP API username"
}

variable "aap_password" {
  type        = string
  description = "AAP API password"
  sensitive   = true
}