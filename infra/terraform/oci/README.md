# infra/terraform/oci

Terraform module for the OCI Always Free infrastructure.

## Resources provisioned

| Resource | File | Description |
|---|---|---|
| VCN + subnet + IGW + route table + security list | `networking.tf` | Single public subnet; port 22 closed — SSH via Bastion only |
| VM.Standard.A1.Flex (4 OCPU / 24 GB) | `compute.tf` | Always-on ARM Ampere A1 instance; cloud-init bootstraps Docker |
| Reserved public IP | `compute.tf` | Survives VM stop/start cycles |
| Bastion service | `bastion.tf` | Time-limited SSH sessions (max 3 h) |
| Object Storage bucket | `storage.tf` | 20 GB free; artefacts + log archives |

## Prerequisites

- OCI Always Free account
- `oci` CLI configured (`~/.oci/config`)
- Terraform ≥ 1.6

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars   # fill in your OCIDs and SSH key
terraform init
terraform plan
terraform apply
```

## ARM A1 capacity note

OCI A1 capacity is sometimes exhausted in popular regions. If you see
`Out of capacity`, try another region (`eu-amsterdam-1`, `ap-singapore-1`).
No state migration is needed if no VM was created in the failed region.

## Post-bootstrap steps

After `terraform apply`, SSH into the VM via the Bastion session and:

```bash
cd /opt/thelook
docker compose up -d
```
