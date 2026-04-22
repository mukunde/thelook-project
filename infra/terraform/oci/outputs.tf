# ─────────────────────────────────────────────────────────────
# OCI module — outputs
# ─────────────────────────────────────────────────────────────

output "vm_public_ip" {
  description = "Reserved public IP of the always-on OCI VM."
  value       = oci_core_public_ip.vm.ip_address
}

# TODO: add bastion FQDN and object storage namespace outputs.
