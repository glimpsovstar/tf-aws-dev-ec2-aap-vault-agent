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
