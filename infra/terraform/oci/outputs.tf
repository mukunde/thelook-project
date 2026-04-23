# ─────────────────────────────────────────────────────────────
# OCI module — outputs
# ─────────────────────────────────────────────────────────────

output "vm_public_ip" {
  description = "Reserved public IP of the always-on OCI VM."
  value       = oci_core_public_ip.vm.ip_address
}

output "vm_instance_ocid" {
  description = "OCID of the VM. Needed to open bastion sessions."
  value       = oci_core_instance.vm.id
}

output "bastion_ocid" {
  description = "OCID of the bastion. Pass this to `oci bastion session create-managed-ssh`."
  value       = oci_bastion_bastion.main.id
}

# TODO: add object storage namespace output once storage.tf is activated.
