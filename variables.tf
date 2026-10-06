variable "aws_region" {
  type    = string
  default = "ap-southeast-2"
}

# Image comes from HCP Packer (RHEL9-SOE: Uptycs EDR, `aap` user, Vault SSH CA).
# HC-COMPUTE-011 requires EDR on every VM, so never pin a stock AMI here.
variable "hcp_packer_bucket" {
  type        = string
  default     = "RHEL9-SOE"
  description = "HCP Packer bucket holding the SOE image."
}

# HCP Packer addresses channels by slug, which is the lower-case channel name.
variable "hcp_packer_channel" {
  type        = string
  default     = "production"
  description = "HCP Packer channel slug to take the image from."
}

# Escape hatch only. It must be an AMI built from the RHEL9-SOE bucket (EDR
# included). Never set it to a stock vendor/marketplace image. AMI ownership
# cannot be checked statically, so this is enforced by review.
variable "ami_override" {
  type        = string
  default     = null
  description = "Optional AMI id that wins over HCP Packer. Must be an SOE build with EDR, not a stock image."

  validation {
    condition     = var.ami_override == null || can(regex("^ami-[0-9a-f]{8,17}$", var.ami_override))
    error_message = "ami_override must be null or a valid AMI id (ami-...)."
  }
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