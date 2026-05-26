resource "terraform_data" "vm_provisioned" {
  input = {
    hostname       = local.vm_names.hostname
    chrony_trigger = var.demo_chrony_trigger
  }

  depends_on = [
    aap_host.vm_host,
    null_resource.wait_for_status_checks,
  ]

  lifecycle {
    action_trigger {
      events  = [after_create]
      actions = [action.aap_workflow_job_launch.aap_post_deployment]
    }
    action_trigger {
      events  = [after_update]
      actions = [action.aap_job_launch.chrony_timesync]
    }
  }
}
