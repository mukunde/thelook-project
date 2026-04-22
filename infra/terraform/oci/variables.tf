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

variable "private_key_path" {
  description = "Path to the PEM private key on the machine running Terraform."
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
  description = "Number of OCPUs allocated to the VM (max 4 on Always Free)."
  type        = number
  default     = 4
}

variable "vm_memory_gb" {
  description = "Memory in GB allocated to the VM (max 24 on Always Free)."
  type        = number
  default     = 24
}

variable "vm_boot_volume_gb" {
  description = "Boot volume size in GB."
  type        = number
  default     = 200
}
