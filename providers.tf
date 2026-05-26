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
  }
}

provider "aws" {
  region = var.aws_region
}

provider "aap" {
  host     = var.aap_host
  username = var.aap_username
  password = var.aap_password
}
