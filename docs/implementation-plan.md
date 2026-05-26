# Implementation Plan — HashiCorp + Red Hat Better Together (AWS Retrofit)

> Companion to [solution-brief.md](solution-brief.md). Plan rewritten on 2026-05-26 after live inspection of the AAP + TFC environment — most assumed work was already done.

## Verified environment state

| Component | Status | Notes |
|---|---|---|
| TFC workspace `tf-aws-dev-ec2-aap-vault-agent` (`ws-565GX2N7WBk8G2m8`) | ✅ | Terraform `~>1.15.0` (last run 1.15.4) — **action triggers fully supported**, no fallback needed |
| TFC VCS integration | ✅ | `glimpsovstar/tf-aws-dev-ec2-aap-vault-agent` on GitHub, push-to-main → auto-plan |
| TFC drift detection (assessments) | ❌ | `assessments-enabled: false` — must turn on |
| TFC notifications → EDA | ❌ | Empty — must add webhook to EDA port 5004 |
| AAP Workflow 24 "AAP Post Deployment" (Day-1) | ✅ | Full chain: parallel Vault Agent + Podman → Security Harden → Validation → SNOW CMDB → Close CR; failure → Raise Incident. `ask_inventory_on_launch: true`, no required extra_vars |
| AAP Workflow 25 "Auto Healing Drift Detection" (Day-N) | ✅ | Get Event → Raise Incident → Pre Plan → Create SNOW CR (waits for approval via `snow_create_cr_wait.yml`) → Remediate Drift → Close. `ask_variables_on_launch: true` |
| AAP project sync (playbooks) | ✅ | `Hashi-RedHat-APJ-Collab/demo-aap-post-deploy`, last sync 2026-05-26 03:51 |
| AAP credentials (Vault, SNOW, TFC, AWS) | ✅ | All present |
| EDA activation "Drift rulebook" | ✅ | Running, rulebook `tfc-webhook.yml`, port 5004, wired to launch Workflow 25 |
| EDA rulebook context passing | ⚠️ | `extra_vars` block commented out — Workflow 25 will fire but won't receive `tfc_workspace_id`/`workspace_name`/`organization_name`. **Needs fix.** Sibling `tfc-webhook-djoo.yml` may be a pre-customized version — check first. |
| Terraform code state | ⚠️ | `main.tf:74-80` uses old `aap_job` resource pointing at `job_template_id=12` (Install Vault Agent only). Needs upgrade to `action "aap_workflow_job_launch"` targeting Workflow 24. |

## What this means for the plan

Original plan assumed 2 full days of build. Actual state means **~3-4 hours of focused work**, with the rest as polish + rehearsal time. The retrofit is much narrower than a port: it's a single Terraform integration upgrade plus three small config touches in TFC + EDA.

---

## Phase 1 — Terraform code upgrade (~1.5h)

**Goal:** Replace the `aap_job` resource with `terraform_data` + `lifecycle.action_trigger` + `action "aap_workflow_job_launch"` pointing at Workflow 24.

### Steps

1. **Update `data.tf`** — add lookup for the workflow template by name (cleaner than hardcoding id 24)
   ```hcl
   data "aap_workflow_job_template" "aap_post_deployment" {
     name = "AAP Post Deployment"
   }
   ```

2. **Create `actions.tf`**
   ```hcl
   action "aap_workflow_job_launch" "aap_post_deployment" {
     config {
       workflow_job_template_id            = data.aap_workflow_job_template.aap_post_deployment.id
       inventory_id                        = aap_inventory.vm_inventory.id
       wait_for_completion                 = true
       wait_for_completion_timeout_seconds = 1800
     }
   }
   ```

3. **Create `lifecycle.tf`**
   ```hcl
   resource "terraform_data" "vm_provisioned" {
     input = local.vm_names

     lifecycle {
       action_trigger {
         events  = [after_create]
         actions = [action.aap_workflow_job_launch.aap_post_deployment]
       }
     }
   }
   ```

4. **Modify `main.tf`** — remove `aap_job.vm_demo_job` (lines 74-80). Keep `aap_inventory` and `aap_host`.

5. **Update `variables.tf`** — `job_template_id` is no longer used. Either remove it, or leave as a transitional unused var. Recommend remove for cleanliness.

6. **Update workspace variable in TFC** — delete `job_template_id` after the Terraform code stops referencing it (or before, since it's currently set to `12` and becomes unused).

7. **Local sanity check** — `terraform init -upgrade && terraform validate`

8. **Commit + push to main** — triggers TFC plan automatically (VCS-wired). Review plan output:
   - Should show: remove `aap_job.vm_demo_job`, add `terraform_data.vm_provisioned`, add the new action resource
   - Should NOT show: any changes to `aws_instance`, `aap_inventory`, or `aap_host`
9. **Apply via TFC UI**

### Phase 1 validation

✅ TFC apply succeeds, Workflow 24 fires in AAP, all 5+ jobs in the chain complete green.
✅ Inventory `Better Together Demo - ws-565GX2N7WBk8G2m8` has the EC2 host registered.
✅ Curl the EC2 public IP on port 8081 — podman httpd should return the demo page.

---

## Phase 2 — TFC + EDA wiring for the drift loop (~1h)

**Goal:** Enable drift detection on the workspace, notify EDA on drift, fix the rulebook so Workflow 25 gets workspace context.

### Steps

1. **Enable assessments (drift detection) on the workspace**
   - TFC UI: workspace → Settings → Health → enable "Drift detection"
   - Or via API: `PATCH /workspaces/ws-565GX2N7WBk8G2m8` with `attributes.assessments-enabled: true`
   - Default cadence: every 24h. For demo, trigger manually via API when needed.

2. **Add TFC notification → EDA webhook**
   - TFC UI: workspace → Settings → Notifications → Add new
   - Destination type: Generic (Webhook)
   - URL: `http://<eda-host>:5004` (replace `<eda-host>` with the actual EDA controller hostname/IP)
   - Triggers: `drift_detected` (and optionally `health_assessment_*`)
   - HMAC: leave blank for demo (currently disabled in rulebook); document as a v2 hardening item

3. **Decide which EDA rulebook to use**
   - Two exist on the synced project: `tfc-webhook.yml` (upstream) and `tfc-webhook-djoo.yml` (presumably your customized one)
   - Open `tfc-webhook-djoo.yml` first — if `extra_vars` is already uncommented and points at Workflow 25, use that one and skip step 4
   - Otherwise edit `tfc-webhook.yml`

4. **Uncomment the `extra_vars` block** in the chosen rulebook so Workflow 25 receives:
   ```yaml
   extra_vars:
     tfc_workspace_id: "{{ event.payload.details.workspace_id }}"
     tfc_workspace_name: "{{ event.payload.details.workspace_name }}"
     tfc_organization_name: "{{ event.payload.details.organization_name }}"
   ```
   These are referenced by `drift-remediate.yml` and `remediate-drift.yml` and are required for the TFC API callback to know which workspace to apply.

5. **Re-sync EDA project + restart the activation** so the rulebook change takes effect.

### Phase 2 validation

✅ TFC notification config shows "enabled" in the workspace settings.
✅ Manually retag the EC2 instance via AWS console (e.g. change `Environment` tag from `Dev` to `DevDrift`).
✅ Trigger a health assessment via TFC API or wait for the next scheduled run.
✅ EDA activation log shows the webhook received the `Drift Detected` event.
✅ Workflow 25 launches in AAP — visible in AAP jobs UI.
✅ SNOW CR appears in your SNOW Dev instance (state: New/Awaiting approval).
✅ Approve the CR in SNOW → workflow resumes → TFC apply runs → tag reverts to `Dev`.

---

## Phase 2.5 — Vault CA-signed SSH bootstrap (~2-3h)

**Goal:** Replace the static `djoo` SSH key (currently used by AAP to reach EC2) with Vault-signed user certificates issued by the `ssh/demo` role on the user's personal Vault. Static key remains only for the bootstrap step.

**Vault decisions (confirmed):**
- Cluster: user's personal Vault (`djoo-test-vault-public-vault-a40e8748...`, namespace `admin`)
- SSH engine + role: `ssh/demo` (default_user=`aap`, TTL 8h, `allowed_users: aap`, `allow_user_certificates: true`)
- Future PKI: `pki-demo/role-pki-demo` (or `pki-demo/internal`) — out of scope for MVP

### Steps

1. **Verify / set up AppRole auth on personal Vault** (~30min)
   - Confirm `approle` auth method is enabled at `auth/approle`
   - Create policy `aap-ssh-signer` granting `update` on `ssh/sign/demo`
   - Create AppRole `aap-ssh-signer` with the policy attached
   - Capture `role_id` and a fresh `secret_id` (sensitive — store via env var, not in chat)

2. **Create new AAP credential pointing at personal Vault** (~15min)
   - Type: "HashiCorp Vault Signed SSH"
   - Name: `vault-signed-ssh-aap-personal`
   - URL: `https://djoo-test-vault-public-vault-a40e8748...:8200`
   - Namespace: `admin`
   - Auth path: `approle`
   - role_id + secret_id from step 1
   - Default username: `aap`
   - Signing role: `demo`

3. **Write bootstrap playbook `0-bootstrap-vault-ssh.yml`** (~45min)
   - In a new repo (or as a PR to `Hashi-RedHat-APJ-Collab/demo-aap-post-deploy`) — coordinate with the upstream maintainer if PR-ing
   - Connects as `ec2-user` (RHEL default) using the **existing static `djoo` machine credential** — the only Day-1 step that uses static auth
   - Creates `aap` user with sudo + same SSH access as ec2-user
   - Fetches `ssh/config/ca` public key from Vault, writes to `/etc/ssh/trusted-user-ca-keys.pem`
   - Adds `TrustedUserCAKeys /etc/ssh/trusted-user-ca-keys.pem` to `/etc/ssh/sshd_config` (idempotent)
   - Reloads sshd
   - Updates the AAP host record so `ansible_user: aap` for subsequent jobs

4. **Add as new AAP job template** (~10min)
   - Name: "Bootstrap Vault SSH"
   - Project: existing `Ansible Automation Post Deploy Demos` (or the new repo if PR-ing upstream)
   - Inventory: linked at launch (Workflow 24 already passes inventory)
   - **Machine credential**: `djoo-aws-demo` (the existing static key cred)

5. **Insert as the FIRST node in Workflow 24** (~15min)
   - Via AAP UI or `POST /workflow_job_template_nodes/`
   - New node fires before Install Vault Agent + Install Application (in parallel)
   - On success, the existing parallel nodes proceed
   - On failure, route to Raise Incident Ticket (same as other nodes)

6. **Switch the other job templates in Workflow 24 to the new Vault Signed SSH credential** (~20min)
   - Install Vault Agent, Install Application, Security Harden, Post Validation
   - Each: detach `djoo-aws-demo`, attach `vault-signed-ssh-aap-personal`
   - Update SNOW CMDB + Close SNOW CR templates only need the SNOW cred — leave alone

### Phase 2.5 validation

✅ Trigger Workflow 24 → bootstrap node succeeds as `ec2-user` with static key.
✅ Subsequent nodes connect as `aap` using a Vault-signed cert (visible in Vault audit log as `ssh/sign/demo` calls).
✅ `vault read sys/audit-hash/file str="<request>"` or audit-tail shows the signing calls during the workflow run.
✅ SSH into the box manually with a Vault-signed cert: `vault write -field=signed_key ssh/sign/demo public_key=@~/.ssh/id_rsa.pub > /tmp/cert.pub && ssh -i ~/.ssh/id_rsa -i /tmp/cert.pub aap@<ec2-ip>` succeeds.

### Phase 2.5 risks

| Risk | Mitigation |
|---|---|
| `ssh/demo` role allows only `aap` user — if cloud-init/AMI default user differs from `ec2-user`, bootstrap might fail | Verify the RHEL9 AMI default user (likely `ec2-user`); adjust bootstrap if `cloud-user` or other |
| Bootstrap playbook idempotency — re-running shouldn't duplicate sshd_config lines | Use `ansible.builtin.lineinfile` with regex match, not `blockinfile` |
| New AAP credential points at a different Vault than existing job templates expect | Existing playbooks (e.g. install-vault-agent) only use Vault for installing Vault Agent on the host — they don't pull AAP-side dynamic secrets. Re-test full Day-1 to be sure |
| AppRole secret_id expiration | Default secret_id TTL is unlimited; if a TTL is set, schedule renewal or use response wrapping |

---

## Phase 3 — README, rehearsals, failure drills (~3-4h)

**Goal:** A separate person can follow the README to a working demo, and you can run the live demo with rehearsed narration and recovery scripts.

### Steps

1. **README rewrite** (~60min)
   - Sections: Prerequisites, Repo layout, Variables, "Run it" (Day-1), "Demo the drift loop" (Day-N), Troubleshooting, Cleanup
   - Prerequisites: HCP TF workspace + Terraform 1.15+, AAP w/ Workflow 24+25, EDA activation, Vault, ServiceNow Dev instance, AWS account
   - Variables: every var in `variables.tf` with example values; mask sensitive ones

2. **Add `terraform.tfvars.example`** (~15min) — concrete examples for every variable, sensitive ones noted.

3. **Cold-clone test** (~45min) — in a separate directory: `git clone <url>` → follow README → time it → capture gotchas → fix.

4. **Demo rehearsal #1 — happy path** (~45min)
   - Destroy → apply → narrate Day-1 → trigger drift → narrate Day-N → final state check
   - Target: full demo under 25 min wall-clock

5. **Failure runbook** (~30min) — write `docs/demo-recovery.md` covering the top 3 likely live-demo failures:
   - TFC apply errors before EC2 boots
   - AAP workflow fails mid-chain (use the "Raise Incident Ticket" branch as narrative)
   - Drift detection lag (have a pre-recorded successful drift run screenshot as backup)

6. **Demo rehearsal #2 — with a deliberate failure injected** (~30min) — practice the recovery narrative for one failure mode.

### Phase 3 validation

✅ Cold-clone-to-working-demo in <30min.
✅ Two clean dry-runs completed.
✅ Failure runbook covers 3 likely live-demo failures.

---

## Stretch — Vault PKI CLM (cut by default, ~2h if attempted)

**Status: cut from MVP.** No existing workflow in AAP, no existing playbook for cert deploy + verify, and no Vault PKI mount confirmed. Re-attempt only if all of Phase 1–3 are clean by mid-Day 2 afternoon.

If attempting: build a separate playbook (`6-issue-pki-cert.yml`?) that uses `community.hashi_vault.vault_write` against the PKI mount, deploys cert to nginx/httpd container, and a verification step that curls HTTPS. New AAP job template + add to Workflow 24 between Security Harden and Post Validation. **Skip unless ahead of schedule.**

---

## Risk register (revised)

| Risk | Likelihood | Mitigation |
|---|---|---|
| EDA activation can't reach Workflow 25 due to AAP API auth | Low | EDA already running, just needs `extra_vars` fix |
| TFC notification webhook can't reach EDA (network/firewall) | Medium | Verify EDA port 5004 is reachable from TFC's IP egress; if not, use ngrok or expose via ALB |
| SNOW CR approval routing not pre-configured | Medium | Check SNOW Dev instance has `CAB Approval` group configured (referenced in `snow_create_cr.yml`); if not, approve directly via API |
| Drift assessment cadence too slow for live demo | High | Trigger assessment via TFC API mid-demo: `POST /workspaces/{id}/assessments` |
| Workflow 24 fails because of a transient SSH/podman issue | Low | First node has `wait_for_connection` (240s); if still flaky, increase timeout |
| Vault lease behavior not visible to audience | Low | Pre-stage a Vault UI tab on the audit log |

---

## Files touched / created

**New files:**
- `actions.tf`
- `lifecycle.tf`
- `terraform.tfvars.example`
- `docs/solution-brief.md` (done)
- `docs/implementation-plan.md` (this file)
- `docs/demo-recovery.md` (Phase 3)

**Modified files:**
- `data.tf` — add `aap_workflow_job_template` lookup
- `main.tf` — remove `aap_job.vm_demo_job` (lines 74-80)
- `variables.tf` — remove `job_template_id` (no longer used)
- `README.md` — full rewrite
- TFC workspace — remove `job_template_id` variable, enable assessments, add notification
- EDA rulebook `tfc-webhook.yml` (or `tfc-webhook-djoo.yml`) — uncomment `extra_vars`

**Untouched:**
- `providers.tf` — provider versions are right (`aap ~> 1.5`, `aws ~> 6.46`)
- `output.tf`
- `aws_instance.rhel_instance` and `aws_ec2_instance_state.rhel_instance_state` in main.tf
- `null_resource.wait_for_status_checks`
- `aap_inventory.vm_inventory` and `aap_host.vm_host`
- IAM instance profile `tfstacks-profile` (Vault Agent auth path)
- AAP workflows 24, 25 — use as-is
- AAP project sync, EDA activation — use as-is

---

## Definition of done

- TFC apply on a clean state runs Workflow 24 end-to-end via action trigger; all chained jobs green
- Drift event flows: AWS tag change → TFC assessment → notification → EDA → Workflow 25 → SNOW CR → approval → TFC apply → reconciliation
- Vault lease create/revoke is observable during AAP job runs
- README permits cold-clone-to-working-demo in <30min
- Failure runbook covers top 3 likely live-demo failures
- Two clean dry-run rehearsals completed
- (Stretch, optional) Vault PKI CLM cert demonstrated
