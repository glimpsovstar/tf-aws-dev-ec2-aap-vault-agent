action "aap_workflow_job_launch" "aap_post_deployment" {
  config {
    workflow_job_template_id            = data.aap_workflow_job_template.aap_post_deployment.id
    inventory_id                        = aap_inventory.vm_inventory.id
    wait_for_completion                 = true
    wait_for_completion_timeout_seconds = 1800
  }
}

# Ad-hoc: subscribes the host to RHEL via rhc connect. Fire on demand from the
# TFC UI:  terraform plan -invoke=action.aap_job_launch.rhel_register
# Credentials come from Vault (aap-kv/rhel-subscription) via the vault provider.
action "aap_job_launch" "rhel_register" {
  config {
    job_template_id                     = data.aap_job_template.rhel_register.id
    inventory_id                        = aap_inventory.vm_inventory.id
    wait_for_completion                 = true
    wait_for_completion_timeout_seconds = 600
    extra_vars = jsonencode({
      rhel_org_id         = data.vault_kv_secret_v2.rhel_subscription.data["org_id"]
      rhel_activation_key = data.vault_kv_secret_v2.rhel_subscription.data["activation_key"]
    })
  }
}

# Ad-hoc: native httpd on RHEL (distinct from the containerized httpd from
# Workflow 24's Install Application step).
action "aap_job_launch" "install_httpd" {
  config {
    job_template_id                     = data.aap_job_template.install_httpd.id
    inventory_id                        = aap_inventory.vm_inventory.id
    wait_for_completion                 = true
    wait_for_completion_timeout_seconds = 600
  }
}

# Wired to after_update of terraform_data.vm_provisioned (see lifecycle.tf).
# Bump var.demo_chrony_trigger to fire this in a demo.
action "aap_job_launch" "chrony_timesync" {
  config {
    job_template_id                     = data.aap_job_template.chrony_timesync.id
    inventory_id                        = aap_inventory.vm_inventory.id
    wait_for_completion                 = true
    wait_for_completion_timeout_seconds = 600
  }
}
