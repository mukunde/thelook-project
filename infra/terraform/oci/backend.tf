# Remote state — Terraform Cloud (free tier)
# Workspace: thelook-oci
# Set TF_TOKEN_app_terraform_io in CI secrets.

terraform {
  backend "remote" {
    organization = "thelook-project"
    workspaces {
      name = "thelook-oci"
    }
  }
}
