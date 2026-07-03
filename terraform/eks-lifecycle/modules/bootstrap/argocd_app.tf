resource "terraform_data" "argocd_app" {
  triggers_replace = [
    var.argocd_repo_url,
    var.argocd_target_revision,
    var.argocd_app_path,
  ]

  provisioner "local-exec" {
    command     = "powershell -ExecutionPolicy Bypass -File ${path.root}/scripts/apply-argocd-app.ps1 -ClusterName ${var.cluster_name} -Region ${var.aws_region} -RepoUrl ${var.argocd_repo_url} -TargetRevision ${var.argocd_target_revision} -AppPath ${var.argocd_app_path}"
    working_dir = path.root
  }

  depends_on = [time_sleep.wait_for_argocd_crds]
}
