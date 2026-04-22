# ─────────────────────────────────────────────────────────────
# Account roles
# 5 roles provisioned up-front as a proof-of-concept of the RBAC pattern.
# Finance is wired to the marts in the initial delivery; Marketing and Ops
# are declared now so the pattern is visible and the grants.tf surface
# stays coherent as the project grows.
# ─────────────────────────────────────────────────────────────

resource "snowflake_account_role" "ingestion" {
  name    = "ROLE_INGESTION"
  comment = "[${var.project_tag}] Owned by dlt. Write access to RAW."
}

resource "snowflake_account_role" "transform" {
  name    = "ROLE_TRANSFORM"
  comment = "[${var.project_tag}] Owned by dbt and Dagster. Read RAW, write ANALYTICS + ANALYTICS_DEV."
}

resource "snowflake_account_role" "analyst_finance" {
  name    = "ROLE_ANALYST_FINANCE"
  comment = "[${var.project_tag}] Read access to Finance marts. Wired in the initial delivery."
}

resource "snowflake_account_role" "analyst_marketing" {
  name    = "ROLE_ANALYST_MARKETING"
  comment = "[${var.project_tag}] Read access to Marketing marts. Wired in a later iteration."
}

resource "snowflake_account_role" "analyst_ops" {
  name    = "ROLE_ANALYST_OPS"
  comment = "[${var.project_tag}] Read access to Operations marts. Wired in a later iteration."
}
