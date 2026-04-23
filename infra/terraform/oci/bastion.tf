# ─────────────────────────────────────────────────────────────
# Bastion service
#
# Provides SSH access to the VM without opening port 22 on the public
# internet. OCI Bastion is included in the Always Free tier.
#
# How access works at runtime:
#   1. User authenticates to OCI (API key / OCI CLI)
#   2. User creates a time-limited session:
#        oci bastion session create-managed-ssh \
#          --bastion-id <bastion_ocid> \
#          --target-resource-id <instance_ocid> \
#          --target-os-username opc \
#          --ssh-public-key-file ~/.ssh/<key>.pub
#   3. OCI returns an `ssh -i <key> -o ProxyCommand=...` command
#   4. SSH is tunnelled through the bastion for the session lifetime (max 3 h)
#
# The bastion itself has its own `client_cidr_block_allow_list` — this
# controls which source IPs can CREATE sessions. Defence-in-depth: even
# with 0.0.0.0/0 here, attackers still need valid OCI IAM credentials
# AND the VM's SSH private key. For a portfolio project with a rotating
# residential IP, 0.0.0.0/0 is a reasonable default.
# ─────────────────────────────────────────────────────────────

variable "bastion_client_cidr_allow_list" {
  description = <<-EOT
    CIDR blocks allowed to create sessions on the bastion.
    Default 0.0.0.0/0 — the bastion still requires OCI IAM + SSH key auth.
    Tighten to ["<your-public-ip>/32"] for stricter defence-in-depth.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "bastion_max_session_ttl_seconds" {
  description = "Max session TTL in seconds. OCI allows 1800 (30 min) to 10800 (3 h)."
  type        = number
  default     = 10800
}

resource "oci_bastion_bastion" "main" {
  bastion_type                 = "STANDARD"
  compartment_id               = var.compartment_ocid
  target_subnet_id             = oci_core_subnet.public.id
  name                         = "thelook-bastion"
  client_cidr_block_allow_list = var.bastion_client_cidr_allow_list
  max_session_ttl_in_seconds   = var.bastion_max_session_ttl_seconds
}
