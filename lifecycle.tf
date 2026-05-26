resource "terraform_data" "vm_provisioned" {
  input = local.vm_names

  depends_on = [
    aap_host.vm_host,
    null_resource.wait_for_status_checks,
  ]

  lifecycle {
    action_trigger {
      events  = [after_create]
      actions = [action.aap_workflow_job_launch.aap_post_deployment]
    }
  }
}
