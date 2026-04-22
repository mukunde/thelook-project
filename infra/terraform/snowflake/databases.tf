# ─────────────────────────────────────────────────────────────
# Databases
# - RAW            : landing zone for dlt ingested data
# - ANALYTICS      : dbt `prod` target (dim_*, fct_*, staging subschemas)
# - ANALYTICS_DEV  : dbt `dev` target + CI schema for state:modified+ runs
# ─────────────────────────────────────────────────────────────

resource "snowflake_database" "raw" {
  name    = "RAW"
  comment = "[${var.project_tag}] Raw landing zone fed by dlt ingestion."
}

resource "snowflake_database" "analytics" {
  name    = "ANALYTICS"
  comment = "[${var.project_tag}] dbt production target (marts, staging)."
}

resource "snowflake_database" "analytics_dev" {
  name    = "ANALYTICS_DEV"
  comment = "[${var.project_tag}] dbt dev target and CI schema for state:modified+ builds."
}

# ─────────────────────────────────────────────────────────────
# Schemas
# dbt itself manages most schemas through custom_schema_name, but we declare
# the top-level ones explicitly so grants can reference them.
# ─────────────────────────────────────────────────────────────

resource "snowflake_schema" "raw_thelook" {
  database = snowflake_database.raw.name
  name     = "THELOOK"
  comment  = "[${var.project_tag}] TheLook eCommerce ingested tables."
}

resource "snowflake_schema" "analytics_staging" {
  database = snowflake_database.analytics.name
  name     = "STAGING"
  comment  = "[${var.project_tag}] dbt staging models (stg_*)."
}

resource "snowflake_schema" "analytics_marts" {
  database = snowflake_database.analytics.name
  name     = "MARTS"
  comment  = "[${var.project_tag}] dbt dimensional marts (dim_*, fct_*)."
}
