action "aap_workflow_job_launch" "aap_post_deployment" {
  config {
    workflow_job_template_id            = data.aap_workflow_job_template.aap_post_deployment.id
    inventory_id                        = aap_inventory.vm_inventory.id
    wait_for_completion                 = true
    wait_for_completion_timeout_seconds = 1800
  }
}
