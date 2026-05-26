# Solution Discovery Output — HashiCorp + Red Hat Better Together on AWS

> Generated via the `solution-discovery-to-validation` skill on 2026-05-26.
> Intended as the upstream brief for the 2-day retrofit; see [implementation-plan.md](implementation-plan.md) for the sequenced build.

## Solution Summary
A live, customer-facing demo built on the existing `tf-aws-dev-ec2-aap-vault-agent` repo. The repo **already works as a Day-1 demo** — EC2 provisioning, AAP inventory/host registration, and an AAP job launch are wired today. The retrofit is two changes layered on that working base:

1. **Upgrade the TFC → AAP integration from the older `aap_job` resource pattern to Terraform actions** (`terraform_data` + `lifecycle.action_trigger` + `action "aap_job_launch"`) — mirrors the pattern in [`_reference-vmware-demo/better-together-vm-lifecycle-dev/lifecycle.tf`](../../_reference-vmware-demo/better-together-vm-lifecycle-dev/lifecycle.tf) but with AWS resources underneath.
2. **Add the Day-N drift loop**: TFC detects drift → EDA receives the webhook → ServiceNow CR created → on approval, EDA calls TFC apply → drift reconciled. EDA rulebooks lift directly from `_reference-vmware-demo/terraform-eda-example` with workspace-name updates.

Vault PKI-based CLM (cert issuance → deploy → verify) is a stretch goal for Day 2 afternoon if time permits.

## Deliverable Type
Shareable demo repo (additive changes to `tf-aws-dev-ec2-aap-vault-agent`) + README runbook sufficient for a live customer walkthrough and for a customer to clone and re-run in their own AWS account.

## Audience
Customers — live demo / workshop format, presented by the user. Mixed technical/decision-maker audience typical for SE-led customer sessions.

## Problem / Opportunity
Customers running RHEL workloads on AWS want to see HashiCorp (Terraform Cloud, Vault) and Red Hat (AAP, EDA) compose into one Day-1 + Day-N automation story without bespoke glue. The existing reference is VMware-centric, which doesn't land for AWS-native customers.

## Desired Outcome
After the demo, the customer can articulate:
- How TFC orchestrates EC2 provisioning AND triggers AAP post-deploy automation in one flow
- How Vault provides dynamic, audited credentials to AAP jobs (no static secrets in playbooks)
- How EDA closes the loop: TFC detects drift → SN CR → approval → TFC apply
- That the pattern is reusable for their own AWS estate (clone the repo, swap vars)

## Scope (MVP — must ship in 2 days)
1. **Day-1 flow upgrade**: replace `aap_job` resource in [main.tf:74-80](../main.tf#L74-L80) with a `terraform_data` + `lifecycle.action_trigger` + `action "aap_job_launch"` pattern. Wire `rhel_register`, `install_nginx`, and `chrony_timesync` (after_update only) as separate job templates.
2. **Day-N drift loop**: lift EDA rulebooks from `terraform-eda-example`, point them at this repo's TFC workspace, configure SN CR creation + approval webhook, and prove the drift → CR → approval → apply loop end-to-end.
3. **Lifted assets** (copy as-is, minimal edits):
   - EDA rulebooks: `tfc-notification-rules.yaml`, `snow-cr-approval-rules.yaml`
   - Ansible roles (if needed in AAP project): `rhel_register`, `chrony_timesync`, `install_nginx`
4. **README runbook** with prerequisites, env vars, run sequence, drift demo flow, and a troubleshooting section.

## Non-Goals (explicit cuts to fit 2 days)
- AD domain join (not in current repo; defer)
- vSphere-derived day-2 ops (power on/off, snapshot, reboot) — drop entirely for MVP
- Vault AWS secrets engine for dynamic IAM (keep existing `tfstacks-profile` instance profile from [main.tf:8](../main.tf#L8); document AWS engine as v2 enhancement)
- Custom Packer-built AMI (keep `var.ami_id` default RHEL9 AMI)
- Multi-region, HA, DR
- AWS Backup integration (VMware `backup_policy` variable)
- CIS hardening role unless trivially copy-pasteable
- Production-grade IAM least-privilege (demo-grade scoping is acceptable)
- Net-new AAP job templates beyond the three named above

## Constraints
- 2-day hard timeline
- Live customer demo — happy path must be rock-solid; failures need scripted recovery
- Existing control plane (HCP TF + AAP/EDA + Vault + ServiceNow) is fixed; no re-provisioning
- Existing `tf-aws-dev-ec2-aap-vault-agent` repo is the base; additive changes only
- AWS region (`ap-southeast-2`) and account must continue to work
- TFC workspace must be on Terraform 1.14+ (required for `action_trigger`) — **verify before Day 1**

## Assumptions
- HCP TF workspace has AWS credentials configured and working (today's demo runs there)
- AAP has existing project/inventory/credential plumbing
- AAP job templates for `rhel_register`, `install_nginx`, `chrony_timesync` exist (or will be created on Day 1 as cheap copies of the current single template)
- Vault PKI mount exists if CLM stretch is attempted; KV mounts referenced by current playbooks already exist
- ServiceNow CR table + approval workflow are pre-configured and reachable from EDA
- The presenter can rehearse the full flow at least once before the customer session
- `aap` provider 1.5+ supports the `aap_job_launch` action resource (matches version pin in [providers.tf:9](../providers.tf#L9))

## Business Benefit
- **Reduced time-to-secure-baseline** for new RHEL workloads on AWS — single TFC trigger replaces manual multi-tool sequencing
- **No static secrets in playbooks** — Vault dynamic creds with audit trail satisfies compliance/security stakeholders
- **Drift as an automated process, not a manual chore** — EDA + SN brings drift into customers' existing change-management workflow
- **Vendor-composable, not vendor-locked** — HashiCorp + Red Hat cooperate at the workflow level; customer keeps existing ITSM

## Evidence / Measurable Indicators
Qualitative (no hard ROI numbers required for this demo):
- Manual steps removed between "I need a new RHEL host" and "host is registered, configured, agents installed" (target: N → 1 trigger)
- Time from drift event to remediation kickoff (target: minutes, with full audit trail)
- Static creds eliminated from playbooks (target: 0)

## Success Criteria
1. Live demo executes Day-1 flow end-to-end from a single TFC trigger; EC2 boots, all three AAP jobs complete green, no manual intervention
2. Live demo executes Day-N drift flow: deliberate drift → TFC detects → SN CR created → manual approval → TFC apply → drift reconciled, all visible to the audience
3. Vault audit shows a lease created when an AAP job runs and revoked at job end (visible in Vault UI/CLI during the demo)
4. A separate person can clone the repo, follow the README, and reach a working demo in their own AWS account within ~30 minutes
5. (Stretch) CLM: nginx on the deployed EC2 serves HTTPS with a Vault PKI-issued cert

## Validation Scenarios
1. **Dry-run rehearsal (Day 2 morning)** — from a destroyed state, trigger TFC apply, time the full Day-1 flow, confirm all AAP jobs complete green
2. **Drift simulation** — manually retag the EC2 via AWS console; confirm TFC drift detection fires within ~15 min, SN CR appears, approval triggers TFC apply, tag is reconciled
3. **Vault lease trace** — during AAP job run, watch `vault list sys/leases/lookup/...` or Vault UI to see lease create/revoke
4. **Cold-clone test** — on a clean checkout (or fresh AWS sub-account if available), follow the README from line 1 → working demo, capture every gotcha
5. **Negative case — TFC apply failure** — inject a deliberate error (bad AMI ID); confirm the demo narration has a recovery path rather than dead air
6. (Stretch) **CLM cert check** — `curl -v https://<ec2-dns>` shows the Vault PKI cert in the TLS handshake

## Open Questions
1. **Job template existence in AAP** — do `rhel_register`, `install_nginx`, `chrony_timesync` already exist as separate templates, or only as a single combined template currently bound to `var.job_template_id`? If only one exists, do we split it on Day 1 morning or just call the same template three times?
2. **TFC workspace Terraform version** — pinned to 1.14+ for action triggers? If on 1.13 or earlier, this is a Day-1-blocker; fallback is multi-`aap_job`-resource pattern.
3. **ServiceNow CR workflow** — is the SN side already wired from a prior demo (CR table fields, approval webhook), or part of the work?
4. **Stretch cut line** — confirm: end of Day 1 afternoon, if drift loop is not green, drop CLM entirely and use Day 2 for polish.

## Recommended Next Step
Produce a sequenced 2-day implementation plan with explicit checkpoints, cut-lines, and "if blocked, skip to" branches. See [implementation-plan.md](implementation-plan.md).
