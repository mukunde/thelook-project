# ─────────────────────────────────────────────────────────────
# Compartment Quotas — hard cap to Always Free resources
#
# Quotas are the only OCI mechanism that BLOCKS provisioning of paid
# resources at creation time (budgets only ALERT after the fact).
# This file is the load-bearing piece of the cost-guardrail strategy
# documented in ADR-0009.
#
# Quota Policy Language reference:
#   https://docs.oracle.com/en-us/iaas/Content/General/Concepts/resourcequotas.htm
#
# Always Free reference (per Oracle, subject to change):
#   - Compute   : 4 OCPU + 24 GB total on VM.Standard.A1.Flex (Ampere ARM)
#                 + 2× VM.Standard.E2.1.Micro (AMD x86)
#   - Block vol : 200 GB total
#   - Object    : 10 GB Standard + 10 GB Archive
#   - Database  : 2× Autonomous (1 OCPU / 20 GB each)
#   - LB        : 1× Flexible LB at 10 Mbps
#   - NAT GW    : 1
#   - VCN       : 2 VCNs
#   - Vault     : 20 keys, 150 secret versions
#
# Statements below intentionally cover the BIGGEST exposures (compute &
# storage) where the unit cost can escalate quickly. Smaller services
# (Vault, Monitoring, Notifications) are not capped here because their
# Always Free limits are generous and their per-unit overage cost is
# negligible — they remain covered by the budget alerts in budget.tf.
# ─────────────────────────────────────────────────────────────

resource "oci_limits_quota" "always_free_only" {
  # Quotas are scoped to the tenancy root; pass tenancy_ocid as compartment_id.
  compartment_id = var.tenancy_ocid
  name           = "thelook-always-free-only"
  description    = "[${var.project_tag}] Restrict provisioning to Always Free shapes/sizes. See ADR-0009."

  # Each statement is evaluated independently; the most restrictive wins.
  # Order does NOT matter — OCI applies all statements as a set.
  statements = [
    # ─── Compute ─────────────────────────────────────────────
    # Block any compute shape that is not part of Always Free.
    # Allowed shapes: VM.Standard.A1.Flex (Ampere ARM) and VM.Standard.E2.1.Micro (AMD x86).
    # Any other shape (Standard.E4.Flex, Standard3, BM.*, GPU.*, dense-IO.*) is denied.
    "Set compute quotas to 0 in tenancy where target.shape != 'VM.Standard.A1.Flex' and target.shape != 'VM.Standard.E2.1.Micro'",

    # Cap A1.Flex to the Always Free total: 4 OCPU and 24 GB across the tenancy.
    # The current VM uses 2 OCPU / 12 GB (see variables.tf comment); the headroom
    # is preserved for a possible future second A1 instance.
    "Set compute quota /standard-a1-core-count/ to 4 in tenancy",
    "Set compute quota /standard-a1-memory-count/ to 24 in tenancy",

    # ─── Block Volume ────────────────────────────────────────
    # Cap total block volume size at the Always Free limit (200 GB).
    # The boot volume of the A1 VM is sized via var.vm_boot_volume_gb (default 200).
    "Set block-storage quota /volume-size-in-gbs/ to 200 in tenancy",

    # ─── Database ────────────────────────────────────────────
    # Block all paid Autonomous Database workloads (DW, OLTP-Pro, APEX-Free is OK).
    # Always Free Autonomous (workloadType = AJD or OLTP with cpu_core_count = 1
    # and data_storage_size_in_tbs = 0.02) remains allowed.
    # Note: this project does NOT currently use ADW — Snowflake is the analytic
    # engine (see ADR-0006). The quota is defensive: if a future change accidentally
    # provisions an ADW, it must explicitly request Always-Free-tier params.
    "Zero database quotas in tenancy where target.workloadType != 'AJD' and target.workloadType != 'OLTP'",

    # ─── Load Balancer ───────────────────────────────────────
    # Cap Flexible LB bandwidth at 10 Mbps (Always Free limit).
    # Anything above (or any classic LB / Network LB beyond free tier) is blocked
    # by the per-resource pricing — this quota explicitly limits flexible LB Mbps.
    "Set load-balancer quota /lb-flexible-bandwidth-count/ to 10 in tenancy",

    # ─── Networking — NAT Gateway ────────────────────────────
    # Cap NAT Gateway count at 1 (Always Free limit).
    # The current networking.tf uses an Internet Gateway, NOT a NAT GW, so this
    # quota effectively blocks the creation of any NAT GW unless it is the only
    # one in the tenancy.
    "Set vcn quota /nat-gateway-count/ to 1 in tenancy",
  ]

  freeform_tags = {
    project = var.project_tag
    purpose = "always-free-cap"
  }
}

# ─────────────────────────────────────────────────────────────
# Extension TODOs (not blockers for the initial €0 cap)
#
# When the project grows and uses additional services, add explicit quotas:
#   - Object Storage      : storage-bytes (10 GB Standard, 10 GB Archive)
#   - Vault / Secrets     : secret-count, key-count
#   - Monitoring          : data-points (metrics ingest)
#   - Notifications       : delivery quotas per channel
#   - Email Delivery      : send quota
#   - Streaming           : partitions, throughput
#   - Functions           : invocations, GB-seconds
#
# Reference list of quota families per service:
#   https://docs.oracle.com/en-us/iaas/Content/General/Concepts/resourcequotas.htm
#
# Do NOT add a quota statement without first reading the official quota name
# for that service — names are not always intuitive and a typo silently does
# nothing (no syntax error, no enforcement).
# ─────────────────────────────────────────────────────────────
