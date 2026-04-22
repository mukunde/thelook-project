# ─────────────────────────────────────────────────────────────
# Compute
# One VM.Standard.A1.Flex ARM Ampere A1 instance with 4 OCPU / 24 GB RAM /
# 200 GB boot volume — the maximum allowed under OCI Always Free when all
# A1 capacity is concentrated on a single VM.
#
# cloud-init bootstraps:
#   - Docker Engine + Compose plugin
#   - fail2ban
#   - unattended-upgrades
#   - A `deploy` user for the Docker Compose stack
# ─────────────────────────────────────────────────────────────

# Latest Canonical Ubuntu 22.04 ARM image in the current region.
data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = var.vm_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# First availability domain in the region.
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Reserved public IP — stays attached to the VM across stop/start cycles.
resource "oci_core_public_ip" "vm" {
  compartment_id = var.compartment_ocid
  display_name   = "thelook-vm-ip"
  lifetime       = "RESERVED"
  private_ip_id  = data.oci_core_private_ips.vm.private_ips[0].id

  depends_on = [oci_core_instance.vm]
}

data "oci_core_private_ips" "vm" {
  subnet_id = oci_core_subnet.public.id

  filter {
    name   = "vnic_id"
    values = [data.oci_core_vnic_attachments.vm.vnic_attachments[0].vnic_id]
  }

  depends_on = [oci_core_instance.vm]
}

data "oci_core_vnic_attachments" "vm" {
  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.vm.id
}

resource "oci_core_instance" "vm" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "thelook-vm"
  shape               = var.vm_shape

  shape_config {
    ocpus         = var.vm_ocpus
    memory_in_gbs = var.vm_memory_gb
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_arm.images[0].id
    boot_volume_size_in_gbs = var.vm_boot_volume_gb
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
    hostname_label   = "thelook"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(file("${path.module}/cloud-init.yaml"))
  }

  # ARM A1 Flex capacity is sometimes saturated — on "Out of Capacity", switch
  # `region` in the tfvars and re-run. No state migration needed as long as
  # no VM was created in the failed region.
}
