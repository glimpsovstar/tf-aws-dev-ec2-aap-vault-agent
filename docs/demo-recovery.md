# Demo Live-Run Recovery Runbook

Companion to [solution-brief.md](solution-brief.md) and [implementation-plan.md](implementation-plan.md). Read once before the customer session. Keep this open in a side tab during the demo.

## Top 3 likely live-demo failures

### 1. TFC apply errors before EC2 boots (AWS-side)

**Symptom:** Plan succeeds, apply errors during `aws_instance` creation. Often an AMI / capacity / IAM message.

**Talk track:** "In a real environment we'd have run policy-as-code via Sentinel/OPA before apply ever ran — most of these issues are caught at plan time. Let me pull the prior successful run and walk through what it would have looked like." Show the previous green run in TFC.

**Recovery:** Cancel the run. Don't try to fix live. Switch narrative to drift detection part of the demo if EC2 already exists from a prior apply.

### 2. AAP workflow node fails mid-chain (Workflow 24)

**Symptom:** TFC apply says `applied`, but in AAP UI the workflow shows individual job failures (Install Vault Agent, Install Application, etc.).

**Talk track:** "Notice the workflow itself reports successful — that's intentional. Failures inside the chain are routed to the Raise Incident Ticket node. In a real environment this would create a SNOW incident automatically, no silent failures. Let me show that." Open the SNOW incident in a side tab.

**Recovery:** No mid-demo fix needed. The failure path running cleanly IS the demo. After the session, click the failed job in AAP → Relaunch.

### 3. Drift detection slow to fire

**Symptom:** You change a tag in AWS, but TFC drift assessment doesn't fire within demo time window.

**Talk track:** "Drift assessments run on a cadence by default — for live demos we trigger them on-demand via API." Then trigger manually:

```bash
export TFE_TOKEN='...'
curl -s -X POST \
  -H "Authorization: Bearer $TFE_TOKEN" \
  -H "Content-Type: application/vnd.api+json" \
  https://app.terraform.io/api/v2/workspaces/ws-565GX2N7WBk8G2m8/assessments
```

**Recovery backup:** If the manual API call also lags, show a screenshot of a prior successful drift run from a rehearsal.

## Mid-demo Vault touchpoints (to call out)

- During `terraform plan`: the run page in TFC will show a `data.vault_kv_secret_v2.rhel_subscription` read. Pause on this. *"The org ID and activation key never live in Terraform code or workspace variables — Vault is the source of record. TFC authenticated via OIDC, got a short-lived token (30 min), read the secret, threw the token away."*
- During AAP jobs that SSH to the host: Vault is signing a user certificate for each connection (after Phase 2.5 lands). Open the Vault audit log in a side tab and grep for `ssh/sign/demo` to show the live signing calls.
- During `1-install-vault-agent.yml`: this installs the Vault Agent itself on the EC2 host, so subsequent Vault interactions can be host-driven. Mention this — it's a less common pattern that lands well with operators.

## Post-demo cleanup

Run these after the customer session.

### Rotate the RHEL activation key

The current activation key `aap-demo` (org `18372743`) appeared in conversation transcripts during the build. It's clearly a demo-scoped key, not prod, so risk is low — but rotate it anyway as hygiene.

1. Generate a new key in the Red Hat Hybrid Cloud Console: https://console.redhat.com/insights/connector/activation-keys
2. Update Vault:

   ```bash
   vault kv put aap-kv/rhel-subscription \
     org_id='18372743' \
     activation_key='<new-key-name>'
   ```

3. Test by firing the ad-hoc action: in TFC UI, plan with `-invoke=action.aap_job_launch.rhel_register`, apply, confirm registration

### Rotate the tokens that appeared in chat

The work was bootstrapped with these tokens shared in conversation — rotate all three:

1. **AAP admin token** (was used to inspect AAP via API): AAP UI → Users → admin → Tokens → revoke the one whose first 6 chars are `lbeBtj`
2. **TFC team token** (was used to inspect TFC + write env vars): TFC UI → Settings → Teams → that team → Tokens → revoke the one starting `LXczM9NK9w...`
3. **Vault TPM-auth token** — auto-rotated by the TPM auth script; no manual action needed

### Things to leave in place

- The new Vault JWT role `auth/tfc/role/aap-vault-agent` — used by this workspace's runs, keep it.
- The policy `aap-vault-agent-rhel-sub` — same.
- The `TFC_VAULT_*` env vars on the workspace — same.
- The new playbooks in `playbooks/` and the AAP job templates pointing at them — same.

## v2 cleanup items (post-MVP)

1. **Switch `data.vault_kv_secret_v2.rhel_subscription` to the ephemeral form** — TFC plans emit a deprecation warning today. The ephemeral resource keeps secret values out of state entirely, a stronger story for the audience. Test in a feature branch — needs verification that `action.config.extra_vars` accepts ephemeral references.
2. **Vault AWS secrets engine for IAM** — replace the static `tfstacks-profile` EC2 instance profile with Vault-issued short-lived AWS creds. Strong "no static cloud creds" narrative.
3. **HMAC verification on the EDA webhook** — currently the `tfc-webhook.yml` rulebook has HMAC commented out. Enable it (TFC notification config supports it) for the production-style story.
4. **Custom Packer-built RHEL AMI** — pre-bake CIS hardening + ssh CA trust + base agents so first-apply is faster.

## Quick-reference links

- TFC workspace: https://app.terraform.io/app/djoo-hashicorp/workspaces/tf-aws-dev-ec2-aap-vault-agent
- AAP controller: https://aap.david-joo.sbx.hashidemos.io
- AAP Workflow 24 (Day-1): https://aap.david-joo.sbx.hashidemos.io/#/templates/workflow_job_template/24
- AAP Workflow 25 (Drift): https://aap.david-joo.sbx.hashidemos.io/#/templates/workflow_job_template/25
- AAP EDA activation (Drift rulebook): https://aap.david-joo.sbx.hashidemos.io/eda
- HCP Vault: https://djoo-test-vault-public-vault-a40e8748.a3bc1cae.z1.hashicorp.cloud:8200 (namespace `admin`)
