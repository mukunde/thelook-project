# ─────────────────────────────────────────────────────────────
# OCI module — input variables
# ─────────────────────────────────────────────────────────────

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
