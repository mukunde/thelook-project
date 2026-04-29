# TheLook Modern Data Stack (Snowflake, dbt, Code-First, IaC)

> A hands-on modern data stack built around the public [TheLook eCommerce](https://console.cloud.google.com/marketplace/product/bigquery-public-data/thelook-ecommerce) dataset. Snowflake as the single analytic engine, Dagster + Metabase running always-on on OCI Free Tier, the whole platform declared via Terraform.

**Status:** Phase 1 (Infrastructure & Governance) closed. Snowflake RBAC, OCI VM, Terraform Cloud workflows, and 10 ADRs are in place. See [`docs/infrastructure-and-governance-phase-report.md`](docs/infrastructure-and-governance-phase-report.md). Phase 2 (data engineering: ingestion, transformation, semantic layer, BI) is in progress.

---

## Live surfaces

The following surfaces are produced by Phase 2. Phase 1 delivered the platform underneath (Snowflake RBAC, OCI VM, Terraform Cloud workflows, cost guardrails) but does not expose end-user surfaces.

| Surface | URL | Availability |
|---|---|---|
| Dagster UI | `https://dagster.<domain>.dev` | Always-on (OCI), Phase 2 |
| Metabase | `https://metabase.<domain>.dev` | Always-on (OCI), Phase 2 |
| Evidence.dev dashboard | `https://<project>.vercel.app` | Always-on (Vercel, static), Phase 2 |
| dbt docs | `https://<user>.github.io/<repo>/` | GitHub Pages, Phase 2 |
| Walk-through video | Loom link | Phase 2 |

---

## Problem

A simulated scale-up e-commerce operates three departments — Finance, Marketing, Operations — that consume the same raw data but compute divergent KPIs. Without a single source of truth, `net_revenue` reported by Finance differs from what Marketing infers, and only Operations factors partial returns into the calculation.

This project implements a **semantic layer** (Cube) as the arbiter: each critical metric has a single definition, and each department layers its own dimensions on top without touching the underlying formula.

## Architecture

```
BigQuery (TheLook)
       │
       │  dlt  (Python, incremental on created_at, cut-off 2023-01-01)
       ▼
Snowflake  ─ RAW ─ ANALYTICS ─ ANALYTICS_DEV
       │
       │  dbt Core  (Kimball star schema, contracts enforced on staging)
       ▼
   dim_* / fct_*  ──►  Cube Cloud (semantic layer)
                           │
                           ├─► Evidence.dev   (static, Vercel)
                           ├─► Metabase       (live, OCI VM)
                           └─► Python notebook (metric unicity check, CI artifact)

Orchestration: Dagster OSS on OCI VM (always-on)
IaC: Terraform — snowflakedb/snowflake + oracle/oci providers
CI/CD: GitHub Actions (lint + state-based dbt build + Terraform plan/apply + Vercel deploy)
```

## Design principles

- **Code-first, versionable everywhere** — every component (ingestion, orchestration, transformations, infrastructure, dashboards) is declared as code under Git, regardless of language (Python, SQL, HCL, YAML), not clicked in a UI.
- **Infrastructure-as-Code** for everything provisionable — Snowflake warehouses and RBAC are declared with the same discipline as the OCI VM.
- **Single analytic engine** — Snowflake only, with no DuckDB mirror and no Oracle Autonomous Database (ADB) fallback. See [ADR-0006](docs/ADR/0006-single-analytic-engine-snowflake.md).
- **Always-on platform, demo-on-demand warehouse** — Dagster + Metabase run permanently on OCI Free Tier at €0; Snowflake is `terraform apply`-ed for active periods and `terraform destroy`-ed afterwards.
- **Documented decisions** — [ten ADRs](docs/ADR/) capture the structuring choices with their trade-offs, plus a [Phase 1 closure report](docs/infrastructure-and-governance-phase-report.md) consolidating the infrastructure and governance work.

## Stack at a glance

| Function | Tool | Hosting | Cost |
|---|---|---|---|
| Source | BigQuery (TheLook) | GCP | €0 |
| Ingestion | dlt | Dagster on OCI | €0 |
| Warehouse | Snowflake | AWS, demo-on-demand | €0 during 30-day trial, capped at 10 credits/month if upgraded (resource monitor) |
| Transformation | dbt Core | Dagster on OCI + CI | €0 |
| Semantic layer | Cube Cloud (dev) | SaaS | €0 |
| Orchestration | Dagster OSS | OCI VM, always-on | €0 |
| BI (static) | Evidence.dev | Vercel | €0 |
| BI (live) | Metabase | OCI VM, always-on | €0 |
| Reverse proxy + TLS | Caddy | OCI VM | €0 |
| IaC | Terraform (dual provider) | Terraform Cloud | €0 |
| CI/CD | GitHub Actions | GitHub | €0 |
| Domain (optional) | Any registrar | — | ~€10/year |

## Repository layout

```
.
├── README.md                                      ← this file
├── LICENSE
├── pyproject.toml                                 ← root Python tooling (ruff, mypy, pytest) via uv
├── .gitignore
├── docs/
│   ├── ADR/                                       ← Architecture Decision Records (ADR-0000 to 0009)
│   └── infrastructure-and-governance-phase-report.md   ← Phase 1 closure report
├── infra/
│   └── terraform/
│       ├── snowflake/                             ← databases, warehouses, roles, grants, users
│       └── oci/                                   ← VCN, VM Ampere A1, Bastion, quotas, budget
└── .github/
    └── workflows/                                 ← Python CI, Terraform CI
```

Phase 2 will add `ingestion/` (dlt), `transformation/` (dbt), `orchestration/` (Dagster), `semantic/` (Cube), `bi/` (Evidence), `notebooks/`, and `infra/docker/` (Docker Compose stack for the OCI VM).

## Getting Started

The Terraform code in `infra/terraform/snowflake/` and `infra/terraform/oci/` is fully reproducible: applied to fresh Snowflake and OCI accounts, it produces the same infrastructure footprint every time. However, the path from "fresh accounts" to "first successful `terraform apply`" requires a one-time manual bootstrap that cannot be expressed in Terraform itself: account creation, MFA enrollment, OCI Pay-As-You-Go upgrade, region subscription, RSA key-pair generation, and Terraform Cloud workspace + sensitive variables setup. Total wall-clock time for the bootstrap: ~1 to 2 hours. Subsequent changes flow through `git push` → TFC apply with zero manual intervention.

<details>
<summary><strong>Click to expand the full bootstrap procedure (~1-2h, one-time)</strong></summary>

### Local tools

Install before you begin.

| Tool | Why | Install |
|---|---|---|
| `git` | Source control | OS package manager |
| Terraform CLI ≥ 1.6 | Local `fmt` / `validate`; remote applies run in TFC | [hashicorp.com/install](https://developer.hashicorp.com/terraform/install) |
| `openssl` | Generate RSA key pairs for Snowflake users | OS package manager |
| `ssh-keygen` | Generate the SSH key pair used by the OCI VM | usually pre-installed |
| `uv` | Python toolchain (used by Phase 2 ingestion) | [astral.sh/uv](https://docs.astral.sh/uv/) |
| `pre-commit` | Run repo's pre-commit hooks locally before push | `pip install pre-commit` |
| `oci` CLI (optional) | Diagnostics; not required for `terraform apply` | [oracle.com/cli](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) |

### Accounts to create

| Account | Tier required | Why | Approx. setup time |
|---|---|---|---|
| GitHub | Free | Source of truth, VCS-driven TFC runs | 5 min |
| Terraform Cloud | Free | Remote state, sensitive variables, workspace runs | 10 min |
| Snowflake | 30-day Trial ($400 credits) | Data warehouse | 5 min |
| OCI | Free Trial → upgraded to Pay-As-You-Go | Always-on platform; PayG required to subscribe additional regions per [ADR-0009](docs/ADR/0009-oci-payg-with-cost-guardrails.md) | 30 min |
| GCP | Free | Source dataset on BigQuery (Phase 2 ingestion). Setup deferred: no GCP credentials are required for Phase 1 (infrastructure and governance). Phase 2 will document service account creation, BigQuery API enablement, and the corresponding TFC variable. | (Phase 2) |

The PayG upgrade exposes a credit card. The €0 TCO commitment is preserved by the four-layer cost defense in `infra/terraform/oci/quotas.tf` and `budget.tf` (Compartment Quotas, Budget canary, MFA, IaC-only). See [ADR-0009](docs/ADR/0009-oci-payg-with-cost-guardrails.md) for the rationale.

### One-time manual console steps

These cannot be expressed in Terraform. Order matters: do them top to bottom.

1. **Snowflake — sign up** at <https://signup.snowflake.com>. Note the account identifier (e.g. `xy12345.eu-west-1.aws`) and the bootstrap user credentials. We refer to this user as `admin_bootstrap`.
2. **Snowflake — enroll MFA** on `admin_bootstrap` (Snowsight → bottom-left user menu → My profile → Multi-factor authentication → Enroll). See [ADR-0008](docs/ADR/0008-admin-bootstrap-retained-as-break-glass.md).
3. **Snowflake — generate `admin_bootstrap` RSA key pair** locally and register the public key (the Snowflake provider authenticates via JWT only, not password):
   ```bash
   mkdir -p ~/.ssh/thelook && cd ~/.ssh/thelook
   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -nocrypt \
     -out admin_bootstrap_rsa_key.p8
   openssl rsa -in admin_bootstrap_rsa_key.p8 -pubout \
     -out admin_bootstrap_rsa_key.pub
   ```
   In Snowsight, run as ACCOUNTADMIN (replace `<KEY_CONTENT>` with the public key without the `-----BEGIN/END-----` lines and without newlines):
   ```sql
   ALTER USER admin_bootstrap SET RSA_PUBLIC_KEY = '<KEY_CONTENT>';
   ```
4. **Snowflake — generate the 5 service user RSA key pairs** (one each for USER_TERRAFORM, USER_DLT, USER_DBT, USER_DAGSTER, USER_CUBE):
   ```bash
   for u in terraform dlt dbt dagster cube; do
     openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -nocrypt \
       -out ${u}_rsa_key.p8
     openssl rsa -in ${u}_rsa_key.p8 -pubout -out ${u}_rsa_key.pub
   done
   ```
   These 5 public keys feed Terraform Cloud variables (next section). The private keys stay on disk for the runtime services that need them (Phase 2). Never commit any of these to git.
5. **OCI — sign up** at <https://www.oracle.com/cloud/free>. Complete identity verification. Note the tenancy OCID and the home region (immutable).
6. **OCI — upgrade the tenancy to Pay-As-You-Go** (Console → Billing & Cost Management → Subscriptions → Upgrade). Required to subscribe additional regions.
7. **OCI — subscribe to a region with reliable A1 capacity**, typically `eu-frankfurt-1` (Console → top-right region menu → Manage Regions → Subscribe). The home region often has saturated A1 capacity; the subscribed region is the one used by Terraform.
8. **OCI — enroll MFA** on the human admin user (Console → Identity & Security → Domains → Default → Users → your user → Authentication → Enable MFA).
9. **OCI — create a dedicated compartment** named `thelook-prod` for the project resources (Console → Identity & Security → Compartments → Create). Note its OCID.
10. **OCI — generate the API key pair** locally and register the public key in OCI Console (Console → User profile → API Keys → Add API Key):
    ```bash
    mkdir -p ~/.oci && chmod 700 ~/.oci
    openssl genrsa -out ~/.oci/thelook_api_key.pem 2048
    chmod 600 ~/.oci/thelook_api_key.pem
    openssl rsa -pubout -in ~/.oci/thelook_api_key.pem \
      -out ~/.oci/thelook_api_key_public.pem
    ```
    Upload `thelook_api_key_public.pem` content to OCI Console; note the fingerprint shown after upload.
11. **OCI — generate the SSH key pair** for the VM (used by the Bastion sessions to authenticate, and as the `ubuntu` user's authorized key via cloud-init):
    ```bash
    ssh-keygen -t rsa -b 4096 -C "thelook-vm" -f ~/.ssh/thelook/oci_vm_rsa
    ```
12. **Terraform Cloud — sign up** at <https://app.terraform.io>. Create an organization (e.g. `thelook-project`).
13. **Terraform Cloud — connect GitHub** (Settings → Providers → VCS Providers → Add → GitHub.com). Required for VCS-driven runs.
14. **Terraform Cloud — create two workspaces**, both VCS-driven, pointing to your fork of this repo:
    - `thelook-snowflake` with working directory `infra/terraform/snowflake`
    - `thelook-oci` with working directory `infra/terraform/oci`

### Configure Terraform Cloud workspace variables

Set these on the corresponding workspace (TFC → Workspace → Variables → Add variable). Mark sensitive variables as such — they will be encrypted at rest by HashiCorp and never re-displayed in plain text.

**`thelook-snowflake` workspace:**

| Variable | Initial value | Sensitive |
|---|---|---|
| `snowflake_organization_name` | your Snowflake org (visible in the account URL) | No |
| `snowflake_account_name` | your Snowflake account | No |
| `snowflake_user` | `admin_bootstrap` | No |
| `snowflake_role` | `ACCOUNTADMIN` | No |
| `snowflake_private_key` | content of `admin_bootstrap_rsa_key.p8` (PEM, full file) | Yes |
| `user_terraform_public_key` | content of `terraform_rsa_key.pub` (no headers, no newlines) | Yes |
| `user_dlt_public_key` | content of `dlt_rsa_key.pub` (no headers, no newlines) | Yes |
| `user_dbt_public_key` | content of `dbt_rsa_key.pub` (no headers, no newlines) | Yes |
| `user_dagster_public_key` | content of `dagster_rsa_key.pub` (no headers, no newlines) | Yes |
| `user_cube_public_key` | content of `cube_rsa_key.pub` (no headers, no newlines) | Yes |

To strip a public key for the `*_public_key` variables:
```bash
awk '!/-----/ {printf "%s", $0}' <key>.pub
```

**`thelook-oci` workspace:**

| Variable | Value | Sensitive |
|---|---|---|
| `tenancy_ocid` | from OCI Console | No |
| `user_ocid` | from OCI Console (your user, not a service user) | No |
| `fingerprint` | from API key registration step | No |
| `private_key` | content of `~/.oci/thelook_api_key.pem` (PEM, full file) | Yes |
| `region` | `eu-frankfurt-1` (or your subscribed region) | No |
| `home_region` | `eu-paris-1` (or your tenancy's home region; required for tenancy-level operations like quotas and budgets) | No |
| `compartment_ocid` | OCID of the `thelook-prod` compartment | No |
| `ssh_public_key` | content of `~/.ssh/thelook/oci_vm_rsa.pub` | No |
| `cost_alert_email` | recipient(s) for budget alerts (comma-separated, no spaces) | No |

### Reproduce the infrastructure

```bash
# 1. Clone the repo
git clone https://github.com/<you>/thelook-project.git
cd thelook-project

# 2. (Optional) Install pre-commit hooks for local validation
pre-commit install

# 3. Snowflake — first apply via TFC (as admin_bootstrap)
# In TFC UI: thelook-snowflake workspace → Actions → Start new run.
# Expected plan: ~25 resources to add (3 databases, 6 schemas, 3 warehouses,
# 5 RBAC roles, 5 service users, 1 resource monitor, ownership transfers).
# Confirm & Apply. Duration: ~3-5 min.

# 4. Snowflake — rotate from admin_bootstrap to USER_TERRAFORM (one-time)
# In TFC UI: thelook-snowflake workspace → Variables → Edit:
#   snowflake_user        = USER_TERRAFORM
#   snowflake_role        = ROLE_TERRAFORM
#   snowflake_private_key = content of terraform_rsa_key.p8
# Save, then trigger a new run.
# Expected plan: "0 to add, 0 to change, 0 to destroy" — confirms the
# rotation is clean and the new identity has the same effective rights.

# 5. OCI — apply via TFC
# In TFC UI: thelook-oci workspace → Actions → Start new run.
# Expected plan: ~14 resources to add (VCN, subnet, IGW, route table,
# security list, NSG, bastion, VM, Reserved IP, quota, budget, 5 alert
# rules). Confirm & Apply. Duration: ~5-10 min.

# 6. OCI VM — wait for cloud-init (~8-12 min after VM "Running" state)
# Cloud-init runs apt update, package upgrade, Docker install, fail2ban,
# unattended-upgrades, deploy user creation, /opt/thelook workspace setup.
# Verify completion via OCI Console → Compute → "thelook-vm" → Metrics
# (CPU usage drops below ~5% when cloud-init finishes).

# 7. OCI VM — verify SSH access via Bastion port-forwarding session
# OCI Console → Identity & Security → Bastion → "thelook-bastion"
# → Create session:
#   Type: SSH port forwarding session
#   IP: <VM private IPv4 from the OCI Console>
#   Port: 22
#   SSH key: ~/.ssh/thelook/oci_vm_rsa.pub
# Then locally, in two terminals:
ssh -i ~/.ssh/thelook/oci_vm_rsa -o ServerAliveInterval=60 \
    -N -L 22000:<vm-private-ip>:22 -p 22 \
    <session-ocid>@host.bastion.<region>.oci.oraclecloud.com
# (other terminal)
ssh -i ~/.ssh/thelook/oci_vm_rsa -p 22000 ubuntu@localhost
```

### What is NOT reproducible from `git clone` + `terraform apply` alone

Honest list of what cannot be eliminated:

- **Account creation** for Snowflake, OCI, Terraform Cloud, GitHub.
- **MFA enrollment** on the Snowflake bootstrap user and the OCI human admin user (provider self-service flows, no API).
- **OCI tenancy upgrade to Pay-As-You-Go** (credit card required, console flow with 3DS).
- **OCI region subscription** post-PayG upgrade (console action).
- **Local RSA key-pair generation** (5 Snowflake service users + 1 OCI API key + 1 SSH key for the VM). The private keys must never be committed.
- **The first Snowflake apply must run as `admin_bootstrap`** (ACCOUNTADMIN); the rotation to `USER_TERRAFORM` is a one-time TFC variable update, documented above and verified by a clean `0/0/0` plan.
- **Terraform Cloud workspace creation and sensitive variables setup** (chicken-and-egg with Terraform-managing-Terraform-Cloud).
- **OCI Bastion sessions** for SSH access (interactive, max 3h TTL, must be re-created when the VM private IP changes).
- **Pre-commit hook installation** locally (`pre-commit install` on first clone).

After this one-time bootstrap (~1-2h), every subsequent change to infrastructure or RBAC flows through:

1. Edit code, commit, push.
2. TFC auto-triggers a plan.
3. Review plan, click Confirm & Apply.
4. Done.

</details>

## Demo-on-demand policy

Snowflake is not running 24/7. Between active periods the warehouse is destroyed to keep cost at strictly €0. When a walkthrough is needed, I run `terraform apply` on the Snowflake module (~5 min) and re-materialize the assets from the Dagster UI (~15 min).

Metabase dashboards keep their last-successful-query results cached, so the live surface stays visually coherent when Snowflake is down. Evidence.dev dashboards are static and carry a "Data snapshot: [date]" banner.

## FinOps

- Warehouses auto-suspend at 60s.
- Ingestion is filtered to data from 2023-01-01 onwards at the source (dlt-level cut-off).
- CI rebuilds only modified dbt models via `dbt build --select state:modified+ --defer`, against a dedicated `ANALYTICS_DEV` schema.
- The always-on platform (Dagster + Metabase + Postgres × 2 + Caddy) runs on OCI Free Tier at €0 in perpetuity.
- A `snowflake_usage` dbt model exposes warehouse credit consumption for monitoring.

## GDPR and Governance

- PII columns are pseudonymized via a deterministic SHA-256 + salt macro at the staging layer.
- A `meta.data_classification` tag (`public` / `internal` / `pii` / `sensitive_pii`) is exposed in dbt docs and drives the Snowflake RBAC.

### RBAC

- Five Snowflake roles (`ROLE_INGESTION`, `ROLE_TRANSFORM`, `ROLE_ANALYST_FINANCE`, `ROLE_ANALYST_MARKETING`, `ROLE_ANALYST_OPS`) are declared in Terraform with least-privilege grants.

## Decision records

| ADR | Decision |
|---|---|
| [ADR-0000](docs/ADR/0000-data-warehouse-snowflake-on-aws.md) | Snowflake on AWS as the data warehouse (foundation) |
| [ADR-0001](docs/ADR/0001-ingestion-dlt-vs-airbyte.md) | dlt over Airbyte for ingestion tooling |
| [ADR-0002](docs/ADR/0002-orchestration-dagster-vs-airflow.md) | Dagster OSS over Airflow for orchestration |
| [ADR-0003](docs/ADR/0003-bi-evidence-metabase-vs-power-bi.md) | Evidence.dev + Metabase over Power BI / Tableau for the BI layer |
| [ADR-0004](docs/ADR/0004-iac-terraform-for-snowflake.md) | Terraform over SQL scripts and Snowsight UI for Snowflake IaC |
| [ADR-0005](docs/ADR/0005-always-on-platform-oci-free-tier.md) | OCI Free Tier as the always-on platform compute |
| [ADR-0006](docs/ADR/0006-single-analytic-engine-snowflake.md) | Snowflake as the single analytic engine |
| [ADR-0007](docs/ADR/0007-semantic-layer-cube-cloud.md) | Cube Cloud as the semantic layer |
| [ADR-0008](docs/ADR/0008-admin-bootstrap-retained-as-break-glass.md) | `admin_bootstrap` retained as break-glass with compensating controls |
| [ADR-0009](docs/ADR/0009-oci-payg-with-cost-guardrails.md) | OCI Pay-As-You-Go with €0 cost guardrails |

## Phase reports

| Phase | Report |
|---|---|
| Phase 1 — Infrastructure & Governance | [Phase 1 closure report](docs/infrastructure-and-governance-phase-report.md) |

## License

MIT — see [LICENSE](LICENSE).
