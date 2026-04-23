# ─────────────────────────────────────────────────────────────
# Warehouses
# Three dedicated warehouses to isolate cost per usage category.
# All XS with aggressive auto-suspend (60s) — FinOps baseline.
# ─────────────────────────────────────────────────────────────

locals {
  warehouse_defaults = {
    warehouse_size      = "XSMALL"
    auto_suspend        = 60
    auto_resume         = "true"
    initially_suspended = true
  }
}

resource "snowflake_warehouse" "ingestion" {
  name                = "INGESTION_WH"
  comment             = "[${var.project_tag}] dlt ingestion runs. Cost-isolated from transform and consumer."
  warehouse_size      = local.warehouse_defaults.warehouse_size
  auto_suspend        = local.warehouse_defaults.auto_suspend
  auto_resume         = local.warehouse_defaults.auto_resume
  initially_suspended = local.warehouse_defaults.initially_suspended
  resource_monitor    = snowflake_resource_monitor.project_budget.name
}

resource "snowflake_warehouse" "transform" {
  name                = "TRANSFORM_WH"
  comment             = "[${var.project_tag}] dbt builds (local, CI, scheduled). Cost-isolated."
  warehouse_size      = local.warehouse_defaults.warehouse_size
  auto_suspend        = local.warehouse_defaults.auto_suspend
  auto_resume         = local.warehouse_defaults.auto_resume
  initially_suspended = local.warehouse_defaults.initially_suspended
  resource_monitor    = snowflake_resource_monitor.project_budget.name
}

resource "snowflake_warehouse" "consumer" {
  name                = "CONSUMER_WH"
  comment             = "[${var.project_tag}] BI consumers (Cube, Metabase, Evidence). Cost-isolated."
  warehouse_size      = local.warehouse_defaults.warehouse_size
  auto_suspend        = local.warehouse_defaults.auto_suspend
  auto_resume         = local.warehouse_defaults.auto_resume
  initially_suspended = local.warehouse_defaults.initially_suspended
  resource_monitor    = snowflake_resource_monitor.project_budget.name
}
