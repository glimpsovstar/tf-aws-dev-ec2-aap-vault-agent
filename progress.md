# progress.md

## Goal / scope
EC2 `tf-aws-dev-ec2-RHEL9-vault-agent` provisioned by HCP Terraform, then configured by AAP over Vault-signed SSH. Public repo: no tenant-specific secrets or URLs.

## Done
- `fix/edr-soe-image`: image now comes from HCP Packer `RHEL9-SOE` channel `production` (HC-COMPUTE-011, EDR), replacing a hard-coded stock AMI. Changing it replaces the instance on next apply.

## In progress
- PR "Use the RHEL9-SOE image from HCP Packer" awaiting review.

## Next
1. Promote a gated RHEL9-SOE version to the `production` channel in HCP Packer.
2. Add `HCP_CLIENT_ID`, `HCP_CLIENT_SECRET`, `HCP_PROJECT_ID` to the workspace variable set.
3. Apply at a convenient time (the instance is replaced; manual Uptycs install is lost).

## Key context
- Validate: `terraform fmt -check -recursive && terraform init -backend=false && terraform validate`.
- `ami_override` (default null) is an escape hatch for SOE builds only, never a stock AMI.
