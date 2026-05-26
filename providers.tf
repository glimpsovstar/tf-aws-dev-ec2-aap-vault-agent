terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.46"
    }
    aap = {
      source  = "ansible/aap"
      version = "~> 1.5"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "aap" {
  host  = var.aap_host
  token = var.aap_token
}

# Auth via TFC dynamic provider credentials (TFC_VAULT_PROVIDER_AUTH=true).
# VAULT_ADDR / VAULT_NAMESPACE / VAULT_TOKEN are injected at run time.
provider "vault" {}
