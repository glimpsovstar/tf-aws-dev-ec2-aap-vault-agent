data "terraform_remote_state" "aws_dev_vpc" {
  backend = "remote"
  config = {
    organization = "djoo-hashicorp"
    workspaces = {
      name = "tf-aws-network-dev"
    }
  }
}
data "terraform_remote_state" "iam_role" {
  backend = "remote"
  config = {
    organization = "djoo-hashicorp"
    workspaces = {
      name = "tf-aws-ec2-iam-role"                 # The name of the TFC workspace for the IAM role
    }
  }
}

data "aap_workflow_job_template" "aap_post_deployment" {
  name              = "AAP Post Deployment"
  organization_name = "Default"
}

# Job templates created from playbooks in this repo (see ./playbooks).
# These are created in AAP against a project that points at this repo;
# names below must match the AAP job template names exactly.
data "aap_job_template" "rhel_register" {
  name              = "Register RHEL Subscription"
  organization_name = "Default"
}

data "aap_job_template" "install_httpd" {
  name              = "Install httpd"
  organization_name = "Default"
}

data "aap_job_template" "chrony_timesync" {
  name              = "Chrony Time Sync"
  organization_name = "Default"
}

# RHEL subscription credentials sourced from Vault at plan time.
# Auth is via TFC dynamic provider credentials (JWT/OIDC) — see providers.tf
# and the TFC_VAULT_* env vars on this workspace.
data "vault_kv_secret_v2" "rhel_subscription" {
  mount = "aap-kv"
  name  = "rhel-subscription"
}
