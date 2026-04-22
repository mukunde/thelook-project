# ─────────────────────────────────────────────────────────────
# Bastion service
# Provides SSH access to the private VM without opening port 22
# on the public internet. Sessions are time-limited (max 3 hours).
# ─────────────────────────────────────────────────────────────

# TODO: uncomment once the VM is created and its OCID is known.

# resource "oci_bastion_bastion" "main" {
#   bastion_type               = "STANDARD"
#   compartment_id             = var.compartment_ocid
#   target_subnet_id           = oci_core_subnet.public.id
#   name                       = "thelook-bastion"
#   client_cidr_block_allow_list = ["0.0.0.0/0"]
#   max_session_ttl_in_seconds = 10800 # 3 hours
# }
