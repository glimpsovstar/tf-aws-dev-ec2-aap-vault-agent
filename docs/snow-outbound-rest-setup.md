# ServiceNow Outbound REST Setup (EDA-driven CR approval)

Configures ServiceNow to POST a webhook to AAP's EDA Event Stream when a
Change Request is approved. The EDA `snow-cr-approval` activation then fires
the `tfc-trigger-apply` job template, which calls HCP Terraform to apply
the workspace identified by the CR's `correlation_id` field.

## Values you'll need when configuring SNOW

These already exist in AAP/EDA — you just plug them into the SNOW Outbound
REST Message in the next section. Nothing to set up on this side.

| What | Value | Where to use it in SNOW |
|---|---|---|
| Endpoint URL | `https://aap.david-joo.sbx.hashidemos.io/eda-event-streams/api/eda/v1/external_event_stream/881f3ecf-37ee-4ab2-870a-29e1275a6cf1/post/` | Outbound REST Message → "Endpoint" field |
| Auth method | HTTP Basic | Outbound REST Message → "Authentication" dropdown |
| Username | `aap-eda-snow` | Basic Auth Profile → "Username" |
| Password | run `cat /tmp/.snow-es-password` in your terminal (kept out of this doc on purpose; rotate after demo) | Basic Auth Profile → "Password" |

For reference only (you don't configure these — SNOW just hits the URL):

| AAP-side object | What it does |
|---|---|
| EDA Event Stream id 2, `snow-approval-stream` | Receives the webhook + verifies Basic auth |
| EDA activation id 4, `snow-cr-approval` (running) | Runs `rulebooks/snow-cr-approval.yml` and fires the JT below on `approval_state == "approved"` |
| Controller Job Template id 32, `tfc-trigger-apply` | Calls the HCP TF API to auto-apply the workspace identified by `correlation_id` |

## SNOW configuration steps

### 1. Create Outbound REST Message

Navigate: **System Web Services → Outbound → REST Message → New**

| Field | Value |
|---|---|
| Name | `eda-cr-approval` |
| Endpoint | `https://aap.david-joo.sbx.hashidemos.io/eda-event-streams/api/eda/v1/external_event_stream/881f3ecf-37ee-4ab2-870a-29e1275a6cf1/post/` |
| Authentication | Basic |
| Basic auth profile | New → Username `aap-eda-snow`, Password from `/tmp/.snow-es-password` |

Save.

### 2. Add HTTP Method

Open the REST Message you just created → HTTP Methods → New

| Field | Value |
|---|---|
| Name | `post` |
| HTTP method | POST |
| Endpoint | (same URL, inherited from parent) |
| HTTP Headers | `Content-Type: application/json` |

Under the **HTTP Request** tab, find the **Content** field at the bottom of the
form (SNOW calls the HTTP body "Content"). Paste:

```json
{
  "approval_state": "approved",
  "correlation_id": "${correlation_id}",
  "cr_number": "${cr_number}",
  "cr_sys_id": "${cr_sys_id}",
  "approver": "${approver}",
  "approver_display": "${approver_display}"
}
```

Submit. Re-open the HTTP Method record — under the **Variable Substitutions**
related list (appears after save), define the five variables you referenced
above: `correlation_id`, `cr_number`, `cr_sys_id`, `approver`,
`approver_display`. Leave defaults blank, optionally add Test values for the
"Test" link.

Switch to the **Authentication** tab and select Authentication type **Basic**,
then pick (or create) a Basic auth profile with username `aap-eda-snow` and
password from `cat /tmp/.snow-es-password`.

Use the **Test** link (under Related Links at the bottom) to verify the
request actually posts to EDA — fill the variables with test values and click
Test. Expect HTTP 200.

### 3. Create Business Rule on `change_request` table

Navigate: **System Definition → Business Rules → New**

| Field | Value |
|---|---|
| Name | `EDA notify on CR approval` |
| Table | `change_request` |
| When | `after` |
| Update | ✓ |
| Filter conditions | `Approval` `changes to` `Approved` (or `State changes to Approved` depending on your CAB workflow) |
| Advanced | ✓ |

Script:

```javascript
(function executeRule(current, previous /*null when async*/) {
  try {
    var r = new sn_ws.RESTMessageV2('eda-cr-approval', 'post');
    r.setStringParameterNoEscape('correlation_id', current.correlation_id.toString() || '');
    r.setStringParameterNoEscape('cr_number',      current.number.toString());
    r.setStringParameterNoEscape('cr_sys_id',      current.sys_id.toString());
    r.setStringParameterNoEscape('approver',       current.sys_updated_by.toString());
    r.setStringParameterNoEscape('approver_display', current.sys_updated_by.getDisplayValue());
    var resp = r.execute();
    gs.log('EDA notified for CR ' + current.number + ': HTTP ' + resp.getStatusCode());
  } catch (ex) {
    gs.error('EDA notify failed for CR ' + current.number + ': ' + ex.message);
  }
})(current, previous);
```

Save.

## End-to-end test

1. Trigger TFC drift assessment in the UI (Health → Drift detection → run now)
2. Watch the chain:
   - TFC notification → EDA activation 3 → `drift-create-snow-tickets` JT runs (~5s)
   - SNOW gets a new Normal CR (state: assess) with `correlation_id = ws-565GX2N7WBk8G2m8`
3. Approve the CR in SNOW (via CAB Approval group, or as admin)
4. Business Rule fires the Outbound REST Message → EDA activation 4 → `tfc-trigger-apply` JT runs
5. TFC creates an auto-applied run, reverts the SG rule
6. SN CR transitions to `closed/successful` via the JT's post-apply task

If anything in the chain breaks, check:
- **Activation 3/4 instance logs:** `https://aap.david-joo.sbx.hashidemos.io/eda/activations/3` and `/4` (Job history tab)
- **EDA event stream events_received counter** on each event stream
- **Business Rule logs** in SNOW (System Logs → System Log → All)

## Post-demo cleanup

In addition to items in `demo-recovery.md`:

- Delete the SNOW Outbound REST Message + Basic Auth Profile + Business Rule
- Rotate or delete the `aap-eda-snow` basic auth credential in EDA (cred id 8)
- Delete the SNOW approval Event Stream (id 2)
- Disable / delete EDA activations 3 + 4
- Optional: keep them around if you'll run this demo again; nothing fires them unless TFC drift triggers or SN posts an approval
