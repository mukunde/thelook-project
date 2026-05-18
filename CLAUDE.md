# CLAUDE.md — context for AI assistants in this repo

## What this project is

`thelook-mds` is a personal modern data stack portfolio project. BigQuery TheLook -> Snowflake (RAW + ANALYTICS) via dlt and dbt, semantic layer on Cube Cloud, BI on Evidence + Metabase, orchestrated by Dagster on OCI Free Tier. Single operator (Gaël Mukunde). €0 TCO. Phase 1 (Infrastructure & Governance) is closed; Phase 2 (data engineering) is in progress.

Architecture principle: **Code-First**. Every component is declared as code under Git, regardless of language. Python is the tactical default where the language is debatable (ingestion, orchestration, notebooks). See [docs/ADR/](docs/ADR/) and [docs/infrastructure-and-governance-phase-report.md](docs/infrastructure-and-governance-phase-report.md).

## Repo layout

```
.
├── infra/terraform/
│   ├── snowflake/        # 3 dbs, 3 wh, 5 roles, 5 service users, resource monitor
│   └── oci/              # VCN, A1 VM, Bastion, quotas, budget
├── infra/docker/         # docker-compose stack (Caddy + Dagster + Metabase) for OCI
├── ingestion/            # dlt pipelines (uv workspace member). Sprint 1: users only.
├── docs/
│   ├── ADR/              # 10 ADRs (0000-0009)
│   └── infrastructure-and-governance-phase-report.md
├── pyproject.toml        # root tooling (ruff, mypy, pytest) + uv workspace
├── uv.lock
├── .pre-commit-config.yaml
└── .github/workflows/    # python-ci.yml, terraform-ci.yml
```

Future Phase 2 additions: `transformation/` (dbt), `orchestration/` (Dagster), `semantic/` (Cube), `bi/evidence/`, `notebooks/`.

## Common commands

```powershell
# Install / sync deps (creates .venv)
uv sync

# Run the ingestion pipeline (Sprint 1)
cd ingestion && uv run python thelook_finance.py

# Tests
uv run pytest                            # all unit tests across workspace
uv run pytest ingestion                  # ingestion module only
uv run pytest ingestion -m integration   # requires GCP + Snowflake credentials

# Lint / format / type-check
uv run ruff check .
uv run ruff format .
uv run mypy .

# Pre-commit (runs on git commit; manual run available)
pre-commit run --all-files
```

Terraform runs through Terraform Cloud (VCS-driven on push). No local `terraform apply` for shared state — only `terraform fmt` / `terraform validate` locally.

## Gotchas

- **Windows line endings**: the pre-commit hook `mixed-line-ending` forces LF. AI-tool edits on Windows often produce CRLF. Expect the first commit attempt to fail with the hook auto-fixing the files; re-stage with `git add` and re-commit.
- **Demo-on-demand Snowflake**: between active periods the warehouse is destroyed. During an active phase (currently in progress), warehouses are XS with 60s auto-suspend and a 10-credit/month resource monitor. Don't issue heavy SELECTs without realising they spin up `INGESTION_WH` / `TRANSFORM_WH` / `CONSUMER_WH` from cold.
- **Cross-cloud ingestion**: source is on GCP, destination on AWS. Small egress cost on the BigQuery side. dlt's incremental cursor (`created_at`) and the `2023-01-01` cut-off keep this bounded.
- **Secret files** that must NEVER be committed: `*.p8`, `*.pem`, `*.key`, `*-service-account.json`, `.dlt/secrets.toml`, `.env`. Already in `.gitignore` but stay vigilant.
- **uv workspace**: root `pyproject.toml` declares `[tool.uv.workspace] members = ["ingestion"]`. Add new modules (`transformation`, `orchestration`, etc.) to this list as Phase 2 progresses, each with its own sub-`pyproject.toml`.

## Where to look for context

- **High-level positioning**: [README.md](README.md)
- **Phase 1 outcomes + lessons**: [docs/infrastructure-and-governance-phase-report.md](docs/infrastructure-and-governance-phase-report.md)
- **Structural decisions and trade-offs**: [docs/ADR/](docs/ADR/) (ADR-0000 to ADR-0009)
- **Snowflake RBAC + databases + warehouses**: [infra/terraform/snowflake/](infra/terraform/snowflake/)
- **Current sprint work**: check `ingestion/`, `transformation/`, etc. (new dirs added per Jalon A sub-step)

## Conventions

- **Commits**: conventional-commit titles (`docs:`, `feat(scope):`, `fix(scope):`, etc.). Body stays concise (1 short sentence) unless extra context is genuinely needed for review.
- **ADRs**: every non-trivial structural decision is recorded in `docs/ADR/` before code is written. Use [docs/ADR/template.md](docs/ADR/template.md).
- **Branches & PRs**: feature branches off `main`, PR review even for single-operator changes (forces explicit recording of intent).
