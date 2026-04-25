# ─────────────────────────────────────────────────────────────
# OCI module — input variables
# ─────────────────────────────────────────────────────────────

variable "project_tag" {
  description = "Short tag prepended to resource descriptions/freeform_tags for traceability. Aligned with the Snowflake module convention."
  type        = string
  default     = "thelook"
}

variable "tenancy_ocid" {
  description = "OCID of the OCI tenancy."
  type        = string
}

variable "user_ocid" {
  description = "OCID of the OCI user used by Terraform."
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the API key registered for the Terraform user."
  type        = string
}

variable "private_key" {
  description = <<-EOT
    PEM-encoded private key content for the OCI user (API key).
    Passed as content (not a path) so it works in Terraform Cloud remote runs.
    For local runs, set via env var:  TF_VAR_private_key="$(cat ~/.oci/oci_api_key.pem)"
    For TFC runs, set as a sensitive workspace variable.
  EOT
  type        = string
  sensitive   = true
}

variable "region" {
  description = "OCI region. Prefer regions with ARM A1 availability (e.g. eu-frankfurt-1)."
  type        = string
  default     = "eu-frankfurt-1"
}

variable "compartment_ocid" {
  description = "OCID of the compartment where resources are created."
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key injected into the VM via cloud-init (for Bastion access)."
  type        = string
}

variable "vm_shape" {
  description = "OCI compute shape. Must be VM.Standard.A1.Flex for Always Free."
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "vm_ocpus" {
  description = <<-EOT
    Number of OCPUs allocated to the VM. Always Free caps at 4 total across
    all A1.Flex VMs in the tenancy. Lowered from 4 to 2 in 2026-04 because
    eu-paris-1 consistently returned `Out of host capacity` for the 4/24
    shape; smaller A1 shapes are generally available when the larger one is
    not. 2 OCPUs is sufficient for Dagster OSS + a few auxiliary containers
    at this project stage; raise back to 4 once capacity returns and the
    platform is under load.
  EOT
  type        = number
  default     = 2
}

variable "vm_memory_gb" {
  description = <<-EOT
    Memory in GB allocated to the VM. Always Free caps at 24 GB total across
    all A1.Flex VMs in the tenancy. Lowered from 24 to 12 alongside vm_ocpus
    for the same A1-capacity reason; the 2-OCPU / 12-GB ratio matches the
    A1.Flex guideline of 6 GB per OCPU.
  EOT
  type        = number
  default     = 12
}

variable "vm_boot_volume_gb" {
  description = "Boot volume size in GB."
  type        = number
  default     = 200
}

# ─── Cost guardrails (see budget.tf, quotas.tf, ADR-0009) ──

variable "cost_alert_email" {
  description = <<-EOT
    Comma-separated list of email addresses receiving OCI Budget alerts.
    Used by every alert rule in budget.tf. Single email is fine; multiple
    addresses must be comma-separated WITHOUT spaces (OCI requirement).
  EOT
  type        = string
}

variable "cost_budget_amount" {
  description = <<-EOT
    Monthly budget cap, expressed in the tenancy currency (see
    cost_budget_currency). Default is 1 — high enough to absorb the
    occasional sub-cent billing artefact, low enough that any meaningful
    spend triggers the 1%/10% alert thresholds. Raise only when there is
    a deliberate decision to allow paid resources (in which case ADR-0009
    must be revisited).
  EOT
  type        = number
  default     = 1
}

variable "cost_budget_currency" {
  description = <<-EOT
    Currency in which cost_budget_amount is interpreted, for human-readable
    alert messages only. OCI Budgets always use the tenancy's billing
    currency; this variable does NOT change that. Set it to whatever your
    tenancy is invoiced in (typically USD or EUR) so the alert text is
    truthful. Default is EUR — this tenancy is invoiced in euros.
  EOT
  type        = string
  default     = "EUR"
}
