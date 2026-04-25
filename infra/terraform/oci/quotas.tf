# ─────────────────────────────────────────────────────────────
# Compartment Quotas — partial hard cap
#
# Quotas BLOCK provisioning of paid resources at creation time. They are
# the hardest layer of the cost-guardrail strategy (ADR-0009). The Budget
# in budget.tf is the secondary, detection-based layer.
#
# Quota Policy Language reference:
#   https://docs.oracle.com/en-us/iaas/Content/General/Concepts/resourcequotas.htm
#
# ─── Important — DSL constraints learned the hard way ──────
#
# 1. Each WHERE clause supports ONLY ONE condition. The DSL does NOT accept
#    `AND` / `OR` to combine conditions in the same statement. Use multiple
#    statements instead, one condition per statement.
#
# 2. Specific quota names (e.g. "standard-a1-core-count") vary per service
#    and per OCI release; many "obvious" names do not actually exist. Always
#    discover the real names against your tenancy before writing them:
#
#      oci limits quota list-quota-family --service-name compute
#      oci limits quota list-quota --service-name compute --quota-family <family>
#
# 3. Family-level statements without a quota name are the most portable form:
#    `Zero <family> quotas in tenancy`
#    `Set <family> quotas to <N> in tenancy [where target.<attr> = 'value']`
#
# Statements below are restricted to the family-level no-WHERE form, which
# is the safest and most reliable. Extend with WHERE-filtered or quota-name
# statements only after verifying the exact syntax against your tenancy.
# ─────────────────────────────────────────────────────────────

resource "oci_limits_quota" "always_free_only" {
  # Quotas are scoped to the tenancy root; pass tenancy_ocid as compartment_id.
  compartment_id = var.tenancy_ocid
  name           = "thelook-always-free-only"
  description    = "[${var.project_tag}] Block paid services unused by the project (database, load-balancer). Compute, block-storage, networking quotas TBD — see TODO. ADR-0009."

  statements = [
    # ─── Database ────────────────────────────────────────────
    # Block ALL Autonomous Database creation. Safe because the project uses
    # Snowflake as its analytic engine (ADR-0006); no ADW/ATP is provisioned
    # or planned. If a future change introduces an Autonomous DB, this
    # statement must be relaxed deliberately — the failure to provision is
    # an intentional speed bump for cost review.
    "Zero database quotas in tenancy",

    # ─── Load Balancer ───────────────────────────────────────
    # Block ALL Load Balancer creation. Safe because SSH access is via the
    # OCI Bastion managed service, not via a public LB. If a future iteration
    # exposes a public HTTP endpoint (e.g. Evidence.dev BI dashboard), this
    # statement must be relaxed AND the Always Free 10 Mbps Flexible LB
    # selected explicitly.
    "Zero load-balancer quotas in tenancy",
  ]

  freeform_tags = {
    project = var.project_tag
    purpose = "always-free-cap"
  }
}

# ─────────────────────────────────────────────────────────────
# TODO — quotas not yet implemented (deferred to ADR-0009 follow-up)
#
# The following exposures are NOT covered by the statements above. They
# remain detected (not blocked) by the Budget canary in budget.tf.
#
# - Compute beyond Always Free (4 OCPU / 24 GB on A1.Flex, 2× E2.1.Micro)
#   - Requires per-shape WHERE-filtered statements; needs the exact valid
#     shape names per region: `oci compute shape list --compartment-id ...`
#   - And the exact quota family names: `oci limits quota list-quota-family
#     --service-name compute`
#
# - Block volume beyond 200 GB total
#   - Needs the actual quota name for total volume size, which differs by
#     region/service version.
#
# - Object Storage beyond 10 GB Standard + 10 GB Archive
#   - Same investigation needed.
#
# - NAT Gateway beyond 1
#   - Same investigation needed; the project uses an Internet Gateway, so
#     the exposure is accidental creation only.
#
# - Flexible Load Balancer beyond 10 Mbps
#   - Already covered by the blanket "Zero load-balancer quotas" above.
#
# Recommended workflow when extending:
#   1. In OCI CLI, list valid families and quota names for the target service.
#   2. Write the statement with EXACT names from step 1.
#   3. terraform plan — if the resource recreates, that's expected.
#   4. terraform apply — if it errors, the OCI error message will name the
#      invalid quota / unsupported syntax explicitly. Iterate from there.
# ─────────────────────────────────────────────────────────────
