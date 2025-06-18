terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.67.0"
    }
    aap = {
      source  = "ansible/aap"
      version = "~> 1"
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
