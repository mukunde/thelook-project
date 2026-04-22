# ─────────────────────────────────────────────────────────────
# Snowflake module — outputs
# ─────────────────────────────────────────────────────────────

output "snowflake_account_url" {
  description = "Full Snowflake account URL."
  value       = "https://${var.snowflake_organization_name}-${var.snowflake_account_name}.snowflakecomputing.com"
}

# TODO: add warehouse, database, and role name outputs as resources land.
