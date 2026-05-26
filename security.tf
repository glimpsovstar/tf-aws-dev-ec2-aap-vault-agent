# Drift-demo security group: a restrictive SSH rule that's the deliberate
# target of the drift loop. Widening this rule's CIDR from 192.168.0.0/24 to
# 0.0.0.0/0 (e.g. via the AWS console) is what an "accidental misconfiguration"
# looks like - TFC detects, EDA picks up the notification, a SNOW Change
# Request is opened, on approval TFC re-applies the original CIDR.
#
# Attached alongside the existing shared SG from tf-aws-network-dev. The
# existing SG still allows SSH so the host is reachable during the demo;
# narrate this new SG as "the production bastion-only path" in the talk track.

data "aws_subnet" "primary" {
  id = data.terraform_remote_state.aws_dev_vpc.outputs.vpc_public_subnets[0]
}

resource "aws_security_group" "demo_ssh_drift" {
  name        = "tf-aws-dev-ec2-aap-vault-agent-drift-demo"
  description = "Drift demo: restrictive SSH (office VPN range only)"
  vpc_id      = data.aws_subnet.primary.vpc_id

  tags = {
    Name      = "demo-ssh-drift"
    Purpose   = "HashiCorp+RedHat better-together demo drift target"
    Terraform = "true"
    Owner     = "djoo"
  }
}

resource "aws_vpc_security_group_ingress_rule" "demo_ssh_office_vpn" {
  security_group_id = aws_security_group.demo_ssh_drift.id
  description       = "SSH from office VPN range only (drift target)"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = "192.168.0.0/24"

  tags = {
    Name = "demo-ssh-drift-rule"
  }
}
