# HashiCorp + Red Hat Better Together on AWS

End-to-end demo that walks a customer through:

1. **Day-1 provisioning** — HCP Terraform provisions a RHEL EC2, then triggers Ansible Automation Platform (AAP) to install Vault Agent, run an application, harden the OS, and validate — all over **Vault CA-signed SSH** (no static keys).
2. **Day-N drift remediation** — TFC detects a drift in the EC2's security group, Event-Driven Ansible (EDA) opens a ServiceNow Change Request, a human approves the CR in SN, and AAP automatically triggers a TFC `apply` to revert the drift. End-to-end automated with one human checkpoint.

Built as the AWS retrofit of the existing VMware-based "better together" demo, sharing the same playbook layer (`Hashi-RedHat-APJ-Collab/demo-aap-post-deploy`) but with AWS-native infrastructure.

---

## Architecture

```text
                    ┌─────────────────────────────────────────────────────────┐
                    │                  Customer's TFC apply                    │
                    └─────────────────────┬───────────────────────────────────┘
                                          │
                                          ▼
   ┌──────────────────────────────────────────────────────────────────────────┐
   │  Terraform code (this repo)                                              │
   │  • aws_instance with user_data: creates `aap` user + installs Vault SSH  │
   │    CA public key into /etc/ssh/trusted-user-ca-keys.pem                  │
   │  • data.vault_kv_secret_v2 reads RHEL subscription from Vault at plan    │
   │    time (TFC OIDC → Vault JWT auth, no static creds)                    │
   │  • action "aap_workflow_job_launch" fires AAP Workflow 24 after_create  │
   └──────────────────────────────┬───────────────────────────────────────────┘
                                  │
                                  ▼ Day-1 (Workflow 24)
   ┌──────────────────────────────────────────────────────────────────────────┐
   │  AAP Workflow 24: "AAP Post Deployment"                                  │
   │  ├─ Install Vault Agent     ──┐                                          │
   │  ├─ Install Application     ──┴─ Security Harden → Post Validation →    │
   │  │  (parallel)                  Update SNOW CMDB → Close SNOW CR        │
   │  └─ Failure path: Raise Incident Ticket                                  │
   │  All host SSH via Vault-signed cert (machine cred: aap-via-vault-signed) │
   └──────────────────────────────────────────────────────────────────────────┘

   ┌──── Day-N drift loop (continuous, event-driven) ─────────────────────────┐
   │                                                                          │
   │   Someone widens SG CIDR in AWS console                                  │
   │                  │                                                       │
   │                  ▼                                                       │
   │   TFC drift assessment detects → POSTs notification to EDA event stream  │
   │                  │                                                       │
   │                  ▼                                                       │
   │   EDA rulebook tfc-drift-detection.yml → fires JT drift-create-snow-     │
   │   tickets → creates SN incident + Normal CR (correlation_id = workspace) │
   │                  │                                                       │
   │                  ▼                                                       │
   │   12 CAB approvers auto-approve (SN PDI demo behavior) → 1 Change Manager │
   │   approval routes to admin → SITS WAITING (the demo's human moment)     │
   │                  │ ← you click Approve in SN                             │
   │                  ▼                                                       │
   │   SN Business Rule fires Outbound REST → EDA event stream                │
   │                  │                                                       │
   │                  ▼                                                       │
   │   EDA rulebook snow-cr-approval.yml → fires JT tfc-trigger-apply         │
   │                  │                                                       │
   │                  ▼                                                       │
   │   TFC auto-applied run → SG CIDR reverted → CR walks Implement → Review  │
   │   → Closed, Incident closes                                              │
   │                                                                          │
   └──────────────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

| Layer | Requirement |
|---|---|
| HCP Terraform | Workspace `tf-aws-dev-ec2-aap-vault-agent` in org `djoo-hashicorp`, VCS-connected to this repo, on Terraform `~>1.15`. Drift detection (assessments) enabled. |
| HCP Terraform env vars on workspace | `TFC_VAULT_PROVIDER_AUTH=true`, `TFC_VAULT_ADDR`, `TFC_VAULT_NAMESPACE=admin`, `TFC_VAULT_AUTH_PATH=tfc`, `TFC_VAULT_RUN_ROLE=aap-vault-agent`, `TFC_VAULT_AUDIENCE=vault.workload.identity` |
| HCP Terraform notification | Generic webhook → EDA event stream `tfc-drift-stream`, trigger `assessment:drifted`, HMAC secret matches the EDA-side cred |
| HCP Vault | Personal Vault. Mounts: `aap-kv` (KV v2 with `rhel-subscription` secret), `ssh` (CA configured + `demo` role). Auth methods: `tfc/` (JWT for TFC), `approle-ssh/` (for AAP) |
| AAP controller | Project `tf-aws-dev-ec2-aap-vault-agent` syncing this repo. Job templates: `Bootstrap Vault SSH`, `drift-create-snow-tickets` (id 31), `tfc-trigger-apply` (id 32), plus Workflow 24's existing JTs. Credentials: `djoo-aws-demo` (break-glass static SSH), `aap-via-vault-signed-ssh` (machine cred with Vault Signed SSH cert plugin), `HCP Terraform API Token - djoo-hashicorp`, `SNOW Dev Instance`. |
| AAP EDA | Project `tf-aws-dev-ec2-aap-vault-agent EDA` syncing this repo's `rulebooks/`. Activations: `tfc-drift-detection`, `snow-cr-approval`. Event streams: `tfc-drift-stream` (HMAC), `snow-approval-stream` (Basic auth). |
| ServiceNow PDI | `dev389292.service-now.com` with: group `TFC Drift Approvers` (admin as member); Outbound REST Message `eda-cr-approval`; Business Rule `EDA notify on CR approval` (table `change_request`, `Approval changes to Approved` + `Correlation ID is ws-565GX2N7WBk8G2m8`). |
| AWS | Account in `ap-southeast-2`. Pre-existing VPC (consumed via remote state from workspace `tf-aws-network-dev`). IAM instance profile `tfstacks-profile` exists. EC2 key pair `djoo-demo-ec2-keypair` exists. |

See [`docs/snow-outbound-rest-setup.md`](docs/snow-outbound-rest-setup.md) for the exact SN configuration.

---

## Running the demo

### Day-1 flow (rebuild from scratch)

1. **Destroy the existing EC2** (if there is one):
   - HCP Terraform UI → workspace → Settings → Destruction → Queue destroy plan
   - Confirm + apply
2. **Trigger a fresh plan**: TFC UI → Actions → Start new run
3. **Confirm + apply** when plan is ready (~30s)
4. **Watch the chain:**
   - EC2 comes up at a new public IP (visible in TFC outputs)
   - On `after_create`, the `aap_workflow_job_launch` action fires Workflow 24 in AAP
   - Workflow 24 runs all jobs over Vault-signed SSH — visible in AAP Jobs UI
5. **Demo moment:** in the Install Vault Agent job stdout, the line `Certificate added: /runner/artifacts/<id>/ssh_key_data-cert.pub (vault-admin-auth-approle-ssh-...)` proves the SSH connection used a Vault-signed cert, not a static key.

### Day-N drift flow

1. **Drift the SG**: in AWS console, EC2 → Security Groups → `tf-aws-dev-ec2-aap-vault-agent-drift-demo` → edit inbound rule → change source from `192.168.0.0/24` to `0.0.0.0/0` → Save.
2. **Trigger drift assessment** (default cadence is hourly; trigger immediately via TFC UI: workspace → Health → Drift detection → run now).
3. **Watch the chain:**
   - TFC detects drift → POSTs to EDA event stream `tfc-drift-stream`
   - EDA activation `tfc-drift-detection` fires JT `drift-create-snow-tickets`
   - SN Incident `INC...` + Change Request `CHG...` appear in SN
   - 12 CAB approvers turn green automatically (SN PDI auto-approve)
   - **1 Change Manager approval sits at `Requested`** routed to admin
4. **Demo moment:** open the CR in SN → click **Approve** on the pending Change Manager approval row. This is the deliberate human checkpoint.
5. **Watch the rest:**
   - SN Business Rule fires → POSTs to EDA event stream `snow-approval-stream`
   - EDA activation `snow-cr-approval` fires JT `tfc-trigger-apply`
   - TFC auto-applied run kicks off → SG CIDR reverts to `192.168.0.0/24`
   - JT walks the CR through Implement → Review → Closed
   - Incident closes

### Ad-hoc operator actions (optional flourish)

Three actions are declared but not auto-fired — invokable from TFC UI for on-demand operator tasks:

```bash
# From terraform CLI configured against the workspace
terraform plan -invoke=action.aap_job_launch.rhel_register
terraform plan -invoke=action.aap_job_launch.install_httpd
terraform plan -invoke=action.aap_job_launch.chrony_timesync
```

(Or invoke from the HCP Terraform UI's actions menu on the workspace.) Useful for "operator can fire one-off automation from the same TFC interface" narrative.

---

## Repository layout

```text
.
├── README.md                          (this file)
├── main.tf                            EC2 + user_data + AAP inventory/host wiring
├── security.tf                        Drift-target SG (the SG the demo deliberately drifts)
├── data.tf                            Remote state + Vault KV lookup + AAP template lookups
├── actions.tf                         Workflow 24 + 3 ad-hoc operator actions
├── lifecycle.tf                       after_create / after_update wiring for the actions
├── providers.tf                       AWS, AAP, Vault provider versions + config
├── variables.tf
├── output.tf
├── playbooks/                         Synced into AAP controller project 27
│   ├── drift-create-snow-tickets.yml  Opens SN incident + Normal CR (no polling)
│   ├── tfc-trigger-apply.yml          POSTs auto-apply run to TFC, walks CR to Closed
│   ├── register-rhel.yml              rhc connect with org+key from Vault
│   ├── install-httpd.yml              Native httpd install
│   ├── chrony-timesync.yml            Time sync after_update demo
│   └── snow-create-cr-readable.yml    (legacy alternative for Workflow 25; not used in EDA flow)
├── rulebooks/                         Synced into AAP EDA project 2
│   ├── tfc-drift-detection.yml        Listens for TFC drift notifications → JT drift-create-snow-tickets
│   └── snow-cr-approval.yml           Listens for SN CR approval webhooks → JT tfc-trigger-apply
└── docs/
    ├── solution-brief.md              Why this demo, who it's for, success criteria
    ├── implementation-plan.md         The build sequence + cut-lines used during construction
    ├── snow-outbound-rest-setup.md    Step-by-step SN configuration
    └── demo-recovery.md               Common live-demo failures + recovery scripts
```

---

## Vault paths used

| Path | Purpose |
|---|---|
| `aap-kv/data/rhel-subscription` | `org_id` + `activation_key` for `rhc connect`. Read by Terraform at plan time. |
| `ssh/sign/demo` | SSH CA signing for the `aap` user. Used by AAP machine credential at SSH time. |
| `ssh/public_key` | Vault SSH CA public key — fetched by EC2 user_data at first boot, installed into `/etc/ssh/trusted-user-ca-keys.pem`. |
| `auth/tfc/role/aap-vault-agent` | JWT/OIDC role bound to this workspace. Lets TFC pull Vault secrets at plan time without static creds. |
| `auth/approle-ssh/role/demo` | AppRole used by AAP to authenticate to Vault for SSH cert signing. |

---

## Talk-track highlights

Three "moments" that pop with a technical customer audience:

1. **TFC plan log line** `data.vault_kv_secret_v2.rhel_subscription` — proves Vault is queried live at plan time, no copying secrets into TFC workspace variables.
2. **AAP job stdout** `Identity added: ...ssh_key_data` followed by `Certificate added: ...ssh_key_data-cert.pub (vault-admin-auth-approle-ssh-...)` — proves SSH used a Vault-signed cert, not a static key, with the Vault auth context embedded in the cert name.
3. **The human-approval pause** in SN — the CR waits at "Assess" with one approval pending until you click. Show your audience the cursor moving to click the Approve button. Then the whole chain finishes autonomously.

---

## Troubleshooting

See [`docs/demo-recovery.md`](docs/demo-recovery.md) for failure modes encountered during build and how to recover live. Highlights:

- **AAP job stuck in "running" with no stdout** — controller wedge, cancel + relaunch
- **`Update SNOW CMDB` fails with `root: Permission denied`** — upstream playbook gathers facts without `connection: local`; workaround: attach a machine credential to the JT
- **TFC plan errors with `failed authenticating to Vault: claim sub does not match`** — JWT role's `bound_claims.sub` doesn't match the actual TFC sub; check project name segment
- **Playbook changes don't appear after `git push`** — AAP project doesn't auto-sync; trigger manually via API or UI

---

## Post-demo cleanup

See `docs/demo-recovery.md` → "Post-demo cleanup" for the full list. Key items:

- Rotate the AAP admin + write tokens used during build
- Rotate the TFC team token
- Rotate the RHEL activation key in Red Hat Hybrid Cloud Console
- Delete `/tmp/.snow-es-password` from the build machine
- Optionally: cancel/close test CRs in SN, deactivate any duplicate Business Rules
