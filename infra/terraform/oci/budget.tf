# ─────────────────────────────────────────────────────────────
# Tenancy budget + alert rules — €0 cost canary
#
# Budgets do NOT block resource creation (that is what Compartment Quotas
# in quotas.tf are for). They DETECT spend and alert by email so that an
# unexpected charge is visible within minutes rather than at month-end.
#
# Strategy: a $1 / month budget with five alert rules. The lowest threshold
# (1% = $0.01) is the canary — it fires on any non-zero charge, regardless
# of source, including charges that bypass the quotas (data egress > 10 TB,
# DDoS amplification, Oracle counting bug, etc.).
#
# Documented in ADR-0009.
#
# Reference:
#   https://docs.oracle.com/en-us/iaas/Content/Billing/Concepts/budgetsoverview.htm
#   https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/budget_budget
#   https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/budget_alert_rule
# ─────────────────────────────────────────────────────────────

resource "oci_budget_budget" "always_free_canary" {
  # Budgets are tenancy-level operations and OCI only allows them against
  # the home region. Pin this resource to the oci.home aliased provider so
  # it works regardless of var.region. The same applies to every alert rule
  # below — they are children of the budget and must use the same provider.
  provider = oci.home

  # Budgets at the tenancy root capture spend across ALL compartments,
  # including ones that may be created later outside this Terraform module.
  compartment_id = var.tenancy_ocid

  display_name = "thelook-always-free-canary"
  description  = "[${var.project_tag}] Tenancy-wide €0 canary. Any actual spend > 1% of the cap fires an email alert. See ADR-0009."

  amount       = var.cost_budget_amount
  reset_period = "MONTHLY"

  # Target the tenancy root so the budget sees spend in every compartment.
  target_type = "COMPARTMENT"
  targets     = [var.tenancy_ocid]

  freeform_tags = {
    project = var.project_tag
    purpose = "always-free-canary"
  }
}

# ─── Alert rules ────────────────────────────────────────────
# Five thresholds, ordered from earliest signal to full breach.
# All send a plain-text email to var.cost_alert_email.
#
# - FORECAST 50% : projection-based; flags trends before money is actually spent.
# - ACTUAL  1%   : the canary (~$0.01) — fires on any non-zero charge.
# - ACTUAL  10%  : confirmation that the 1% wasn't a transient billing artefact.
# - ACTUAL  50%  : real escalation; investigate immediately.
# - ACTUAL 100%  : full budget breach; quota policy must be tightened or
#                  PayG cap raised intentionally.

resource "oci_budget_alert_rule" "forecast_50pct" {
  provider     = oci.home
  budget_id    = oci_budget_budget.always_free_canary.id
  display_name = "thelook-forecast-50pct"
  description  = "Forward-looking warning: month-end forecast crosses 50% of the cap."

  type           = "FORECAST"
  threshold      = 50
  threshold_type = "PERCENTAGE"

  recipients = var.cost_alert_email
  message    = "OCI tenancy month-end FORECAST has crossed 50% of the ${var.cost_budget_amount} ${var.cost_budget_currency} cap. Spend is trending up; investigate the Cost Analysis dashboard."
}

resource "oci_budget_alert_rule" "actual_1pct" {
  provider     = oci.home
  budget_id    = oci_budget_budget.always_free_canary.id
  display_name = "thelook-actual-1pct"
  description  = "Canary: any non-zero actual spend (~$0.01)."

  type           = "ACTUAL"
  threshold      = 1
  threshold_type = "PERCENTAGE"

  recipients = var.cost_alert_email
  message    = "OCI tenancy ACTUAL spend has crossed 1% of the ${var.cost_budget_amount} ${var.cost_budget_currency} cap. Investigate immediately — Always Free should produce €0."
}

resource "oci_budget_alert_rule" "actual_10pct" {
  provider     = oci.home
  budget_id    = oci_budget_budget.always_free_canary.id
  display_name = "thelook-actual-10pct"
  description  = "Confirmation that the 1% canary is not a transient billing artefact."

  type           = "ACTUAL"
  threshold      = 10
  threshold_type = "PERCENTAGE"

  recipients = var.cost_alert_email
  message    = "OCI tenancy ACTUAL spend has crossed 10% of the ${var.cost_budget_amount} ${var.cost_budget_currency} cap. Confirms the canary."
}

resource "oci_budget_alert_rule" "actual_50pct" {
  provider     = oci.home
  budget_id    = oci_budget_budget.always_free_canary.id
  display_name = "thelook-actual-50pct"
  description  = "Escalation threshold."

  type           = "ACTUAL"
  threshold      = 50
  threshold_type = "PERCENTAGE"

  recipients = var.cost_alert_email
  message    = "OCI tenancy ACTUAL spend has crossed 50% of the ${var.cost_budget_amount} ${var.cost_budget_currency} cap. Escalation: identify the leaking resource and either delete it or tighten the quota policy."
}

resource "oci_budget_alert_rule" "actual_100pct" {
  provider     = oci.home
  budget_id    = oci_budget_budget.always_free_canary.id
  display_name = "thelook-actual-100pct"
  description  = "Full breach of the cap."

  type           = "ACTUAL"
  threshold      = 100
  threshold_type = "PERCENTAGE"

  recipients = var.cost_alert_email
  message    = "OCI tenancy ACTUAL spend has crossed 100% of the ${var.cost_budget_amount} ${var.cost_budget_currency} cap. The €0 strategy has failed for this billing period — root-cause and update quotas/budget."
}
