# ─────────────────────────────────────────────────────────────
# Terraform RBAC — ROLE_TERRAFORM + USER_TERRAFORM
#
# This file replaces the bootstrap ACCOUNTADMIN identity used for the
# initial `terraform apply`. After this module is applied (still as
# ACCOUNTADMIN):
#
#   1. ROLE_TERRAFORM exists with SYSADMIN + USERADMIN + SECURITYADMIN
#      privileges inherited, plus MODIFY ON ACCOUNT for resource monitors.
#   2. USER_TERRAFORM exists with key-pair auth and ROLE_TERRAFORM as
#      default role.
#   3. Ownership of every module-managed object is transferred from
#      ACCOUNTADMIN to ROLE_TERRAFORM, so subsequent applies as
#      USER_TERRAFORM have the rights to modify them.
#
# Post-apply rotation (outside Terraform):
#   - Update the TFC workspace variables:
#       snowflake_user        = USER_TERRAFORM
#       snowflake_role        = ROLE_TERRAFORM
#       snowflake_private_key = <new .p8 content>
#   - Run `terraform plan` → must return `0 to add, 0 to change, 0 to destroy`.
#   - Disable admin_bootstrap:
#       ALTER USER <admin_bootstrap> SET DISABLED = TRUE;
# ─────────────────────────────────────────────────────────────

# ─── Input ─────────────────────────────────────────────────

variable "user_terraform_public_key" {
  description = <<-EOT
    RSA public key (PEM, without headers/footers) for USER_TERRAFORM.
    Generated locally via:
      openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -nocrypt -out terraform_rsa_key.p8
      openssl rsa -in terraform_rsa_key.p8 -pubout -out terraform_rsa_key.pub
    Strip headers/newlines before pasting into the TFC variable.
  EOT
  type        = string
  default     = ""
}

# ─── Role ──────────────────────────────────────────────────

resource "snowflake_account_role" "terraform" {
  name    = "ROLE_TERRAFORM"
  comment = "[${var.project_tag}] Owned by Terraform. Inherits SYSADMIN + USERADMIN + SECURITYADMIN + MODIFY ON ACCOUNT."
}

# ─── Role inheritance (grant admin roles INTO ROLE_TERRAFORM) ─────

resource "snowflake_grant_account_role" "terraform_inherits_sysadmin" {
  role_name        = "SYSADMIN"
  parent_role_name = snowflake_account_role.terraform.name
}

resource "snowflake_grant_account_role" "terraform_inherits_useradmin" {
  role_name        = "USERADMIN"
  parent_role_name = snowflake_account_role.terraform.name
}

resource "snowflake_grant_account_role" "terraform_inherits_securityadmin" {
  role_name        = "SECURITYADMIN"
  parent_role_name = snowflake_account_role.terraform.name
}

# MODIFY on ACCOUNT enables creation/alteration of resource monitors,
# which is otherwise ACCOUNTADMIN-only.
resource "snowflake_grant_privileges_to_account_role" "terraform_account_modify" {
  account_role_name = snowflake_account_role.terraform.name
  privileges        = ["MODIFY"]
  on_account        = true
}

# ─── User ──────────────────────────────────────────────────

resource "snowflake_user" "terraform" {
  name           = "USER_TERRAFORM"
  comment        = "[${var.project_tag}] Service user assumed by Terraform Cloud runs."
  default_role   = snowflake_account_role.terraform.name
  rsa_public_key = var.user_terraform_public_key
}

resource "snowflake_grant_account_role" "terraform_user_has_terraform_role" {
  role_name = snowflake_account_role.terraform.name
  user_name = snowflake_user.terraform.name
}

# ─── Ownership transfers ─────────────────────────────────────
# Every module-managed object is transferred from ACCOUNTADMIN
# (the bootstrap identity) to ROLE_TERRAFORM, so subsequent
# Terraform runs as USER_TERRAFORM can manage them.
#
# Grouped by object type for readability.

resource "snowflake_grant_ownership" "terraform_owns_warehouses" {
  for_each = {
    ingestion = snowflake_warehouse.ingestion.name
    transform = snowflake_warehouse.transform.name
    consumer  = snowflake_warehouse.consumer.name
  }

  account_role_name   = snowflake_account_role.terraform.name
  outbound_privileges = "COPY"

  on {
    object_type = "WAREHOUSE"
    object_name = each.value
  }
}

resource "snowflake_grant_ownership" "terraform_owns_databases" {
  for_each = {
    raw           = snowflake_database.raw.name
    analytics     = snowflake_database.analytics.name
    analytics_dev = snowflake_database.analytics_dev.name
  }

  account_role_name   = snowflake_account_role.terraform.name
  outbound_privileges = "COPY"

  on {
    object_type = "DATABASE"
    object_name = each.value
  }
}

resource "snowflake_grant_ownership" "terraform_owns_schemas" {
  for_each = {
    raw_thelook       = "\"${snowflake_database.raw.name}\".\"${snowflake_schema.raw_thelook.name}\""
    analytics_staging = "\"${snowflake_database.analytics.name}\".\"${snowflake_schema.analytics_staging.name}\""
    analytics_marts   = "\"${snowflake_database.analytics.name}\".\"${snowflake_schema.analytics_marts.name}\""
  }

  account_role_name   = snowflake_account_role.terraform.name
  outbound_privileges = "COPY"

  on {
    object_type = "SCHEMA"
    object_name = each.value
  }
}

resource "snowflake_grant_ownership" "terraform_owns_roles" {
  for_each = {
    ingestion         = snowflake_account_role.ingestion.name
    transform         = snowflake_account_role.transform.name
    analyst_finance   = snowflake_account_role.analyst_finance.name
    analyst_marketing = snowflake_account_role.analyst_marketing.name
    analyst_ops       = snowflake_account_role.analyst_ops.name
  }

  account_role_name   = snowflake_account_role.terraform.name
  outbound_privileges = "COPY"

  on {
    object_type = "ROLE"
    object_name = each.value
  }
}

resource "snowflake_grant_ownership" "terraform_owns_users" {
  for_each = {
    dlt     = snowflake_user.dlt.name
    dbt     = snowflake_user.dbt.name
    dagster = snowflake_user.dagster.name
    cube    = snowflake_user.cube.name
  }

  account_role_name   = snowflake_account_role.terraform.name
  outbound_privileges = "COPY"

  on {
    object_type = "USER"
    object_name = each.value
  }
}

# Resource monitor ownership is a special case: Snowflake's default
# policy restricts RM operations to ACCOUNTADMIN. The MODIFY ON ACCOUNT
# grant above gives ROLE_TERRAFORM the right to manage RMs. If ownership
# transfer on this object type fails at apply time, a fallback is to
# remove this block and manage the RM manually as ACCOUNTADMIN.
resource "snowflake_grant_ownership" "terraform_owns_resource_monitor" {
  account_role_name   = snowflake_account_role.terraform.name
  outbound_privileges = "COPY"

  on {
    object_type = "RESOURCE MONITOR"
    object_name = snowflake_resource_monitor.project_budget.name
  }
}
