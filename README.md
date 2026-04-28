# TheLook Modern Data Stack (Python-First, IaC, Self-Hosted)

> A hands-on modern data stack built around the public [TheLook eCommerce](https://console.cloud.google.com/marketplace/product/bigquery-public-data/thelook-ecommerce) dataset. Snowflake as the single analytic engine, Dagster + Metabase running always-on on OCI Free Tier, the whole platform declared via Terraform.

**Status:** Phase 1 (Infrastructure & Governance) closed. Snowflake RBAC, OCI VM, Terraform Cloud workflows, and 10 ADRs are in place. See [`docs/infrastructure-and-governance-phase-report.md`](docs/infrastructure-and-governance-phase-report.md). Phase 2 (data engineering: ingestion, transformation, semantic layer, BI) is in progress.

---

## Live surfaces

The following surfaces are produced by Phase 2. Phase 1 delivered the platform underneath (Snowflake RBAC, OCI VM, Terraform Cloud workflows, cost guardrails) but does not expose end-user surfaces.

| Surface | URL | Availability |
|---|---|---|
| Dagster UI | `https://dagster.tondomaine.dev` | Always-on (OCI), Phase 2 |
| Metabase | `https://metabase.tondomaine.dev` | Always-on (OCI), Phase 2 |
| Evidence.dev dashboard | `https://<project>.vercel.app` | Always-on (Vercel, static), Phase 2 |
| dbt docs | `https://<user>.github.io/<repo>/` | GitHub Pages, Phase 2 |
| Walk-through video | Loom link | Phase 2 |

---

## Problem

A simulated scale-up e-commerce operates three departments — Finance, Marketing, Operations — that consume the same raw data but compute divergent KPIs. Without a single source of truth, `net_revenue` reported by Finance differs from what Marketing infers, and Operations ignores partial returns entirely.

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

- **Python-first** for all code (ingestion, orchestration, analytical notebooks).
- **Infrastructure-as-Code** for everything provisionable — Snowflake warehouses and RBAC are declared with the same discipline as the OCI VM.
- **Single analytic engine** — Snowflake, no DuckDB mirror, no ADB fallback. See [ADR-0006](docs/ADR/0006-single-analytic-engine-snowflake.md).
- **Always-on platform, demo-on-demand warehouse** — Dagster + Metabase run permanently on OCI Free Tier at €0; Snowflake is `terraform apply`-ed for active periods and `terraform destroy`-ed afterwards.
- **Documented decisions** — [ten ADRs](docs/ADR/) capture the structuring choices with their trade-offs, plus a [Phase 1 closure report](docs/infrastructure-and-governance-phase-report.md) consolidating the infrastructure and governance work.

## Stack at a glance

| Function | Tool | Hosting | Cost |
|---|---|---|---|
| Source | BigQuery (TheLook) | GCP | €0 |
| Ingestion | dlt | Dagster on OCI | €0 |
| Warehouse | Snowflake on AWS | Cloud, demo-on-demand | €0 during 30-day trial, capped at 10 credits/month if upgraded (resource monitor) |
| Transformation | dbt Core | Dagster on OCI + CI | €0 |
| Semantic layer | Cube Cloud (dev) | SaaS Free | €0 |
| Orchestration | Dagster OSS | OCI VM, always-on | €0 |
| BI (static) | Evidence.dev | Vercel Free | €0 |
| BI (live) | Metabase | OCI VM, always-on | €0 |
| Reverse proxy + TLS | Caddy | OCI VM | €0 |
| IaC | Terraform (dual provider) | Terraform Cloud Free | €0 |
| CI/CD | GitHub Actions | GitHub Free | €0 |
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

## Getting started

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.6
- [uv](https://docs.astral.sh/uv/) for the Python toolchain
- A Snowflake account (30-day trial or paid plan; resource monitor caps usage at 10 credits/month)
- An OCI account with the `oci-cli` configured (Free Trial sufficient initially; Pay-As-You-Go required to subscribe additional regions, see [ADR-0009](docs/ADR/0009-oci-payg-with-cost-guardrails.md))
- A Terraform Cloud Free account with a workspace per module

### Install Python tooling

```bash
uv sync
```

This installs the dev tools (ruff, mypy, pytest) defined in [`pyproject.toml`](pyproject.toml).

### Provision Snowflake

```bash
cd infra/terraform/snowflake
cp terraform.tfvars.example terraform.tfvars   # fill in your values
terraform init
terraform plan
terraform apply
```

See [`infra/terraform/snowflake/README.md`](infra/terraform/snowflake/README.md) for the full variable list and role layout.

### Provision the OCI VM

```bash
cd infra/terraform/oci
cp terraform.tfvars.example terraform.tfvars   # fill in your values
terraform init
terraform plan
terraform apply
```

See [`infra/terraform/oci/README.md`](infra/terraform/oci/README.md) for region strategy (ARM A1 capacity considerations) and post-bootstrap steps.

### Deploy the Docker Compose stack on the VM

```bash
cd infra/docker
cp .env.example .env                           # fill in your values
# Transfer this directory to the OCI VM via OCI Bastion, then:
docker compose up -d
```

See [`infra/docker/README.md`](infra/docker/README.md) for TLS setup and the public service layout.

## Demo-on-demand policy

Snowflake is not running 24/7. Between active periods the warehouse is destroyed to keep cost at strictly €0. When a walkthrough is needed, I run `terraform apply` on the Snowflake module (~5 min) and re-materialize the assets from the Dagster UI (~15 min).

Metabase dashboards keep their last-successful-query results cached, so the live surface stays visually coherent when Snowflake is down. Evidence.dev dashboards are static and carry a "Data snapshot: [date]" banner.

## FinOps

- Warehouses auto-suspend at 60s.
- Ingestion is filtered to data from 2023-01-01 onwards at the source (dlt-level cut-off).
- CI rebuilds only modified dbt models via `dbt build --select state:modified+ --defer`, against a dedicated `ANALYTICS_DEV` schema.
- The always-on platform (Dagster + Metabase + Postgres × 2 + Caddy) runs on OCI Free Tier at €0 in perpetuity.
- A `snowflake_usage` dbt model exposes warehouse credit consumption for monitoring.

## GDPR notes

- PII columns are pseudonymized via a deterministic SHA-256 + salt macro at the staging layer.
- A `meta.data_classification` tag (`public` / `internal` / `pii` / `sensitive_pii`) is exposed in dbt docs and drives the Snowflake RBAC.
- Ingestion applies a hard cut-off at 2023-01-01 for data minimization.
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
