# ─────────────────────────────────────────────────────────────
# Snowflake module — input variables
# ─────────────────────────────────────────────────────────────

variable "snowflake_organization_name" {
  description = "Snowflake organisation name (visible in the account URL)."
  type        = string
}

variable "snowflake_account_name" {
  description = "Snowflake account name within the organisation."
  type        = string
}

variable "snowflake_user" {
  description = "Service-account user used by Terraform (uses JWT auth)."
  type        = string
}

variable "snowflake_private_key" {
  description = "PEM-encoded RSA private key for Terraform's JWT auth. Keep out of VCS."
  type        = string
  sensitive   = true
}

variable "snowflake_role" {
  description = "Snowflake role assumed by Terraform (SYSADMIN or a dedicated TF role)."
  type        = string
  default     = "SYSADMIN"
}

variable "project_tag" {
  description = "Short tag prepended to resource comments for traceability (e.g. 'thelook')."
  type        = string
  default     = "thelook"
}
