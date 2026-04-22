# ─────────────────────────────────────────────────────────────
# Object Storage
# OCI Always Free includes 20 GB of object storage.
# Used for: Terraform state backups, dbt artefacts, log archives.
# ─────────────────────────────────────────────────────────────

# TODO: define bucket once naming convention is confirmed.

# resource "oci_objectstorage_bucket" "thelook" {
#   compartment_id = var.compartment_ocid
#   namespace      = data.oci_objectstorage_namespace.ns.namespace
#   name           = "thelook-artefacts"
#   access_type    = "NoPublicAccess"
#   storage_tier   = "Standard"
# }

# data "oci_objectstorage_namespace" "ns" {
#   compartment_id = var.compartment_ocid
# }
