# ADR-0001: Ingestion tooling — dlt over Airbyte

- **Status**: Accepted
- **Date**: 2026-04-20
- **Tags**: ingestion, python-first, tco

## Context and Problem Statement

The project ingests data from the public TheLook eCommerce dataset (hosted on GCP BigQuery) into Snowflake. Ingestion runs daily and must remain reproducible, cheap to operate, and consistent with the Python-first choices made elsewhere in the stack.

The ingestion layer must integrate with Dagster, run in CI for integration tests, and keep secrets handling simple on both local workstations and the OCI-hosted orchestrator.

## Decision Drivers

- **Python-first stack consistency**: Dagster and custom code are already Python-native; the ingestion tool should not force a context switch.
- **Operational simplicity**: the orchestrator already runs on a single OCI VM. Adding a heavy ingestion platform (the Airbyte stack requires its own Postgres + Temporal + multiple containers) would consume a large portion of the free-tier VM resources.
- **Code-review culture**: pipelines must be versioned, testable with `pytest`, and reviewable in Pull Requests like any other code.
- **Incremental loading**: the dataset supports `created_at`-based incremental loading; the tool must offer a first-class primitive for this.
- **Native Dagster integration**: each ingestion pipeline should be expressable as a Dagster asset without glue code.
- **TCO**: ingestion tooling must stay at €0.

## Considered Options

- **dlt** (data load tool) — Python library, code-first, no UI, incremental primitives built-in.
- **Airbyte OSS** — connector marketplace, UI-driven, Docker Compose stack (Postgres + Temporal + workers).
- **Fivetran** — SaaS, proprietary, excluded by the €0 TCO constraint.
- **Custom Python scripts** — maximum flexibility, maximum maintenance burden, no incremental primitives out of the box.

## Decision

I chose **dlt**. It is the only option that satisfies all six drivers at once: a pure Python library, native Dagster integration, incremental loading as a first-class feature, and it runs anywhere Python runs (local, CI, OCI VM) without additional infrastructure.

## Consequences

### Positive

- Ingestion code lives in the same repo, goes through the same PR review process, and is linted (`ruff`, `mypy`) and tested (`pytest`) like any other Python module.
- Zero infrastructure overhead beyond the Python environment already required for Dagster and dbt.
- Native secrets handling via `.dlt/secrets.toml` (local) and environment variables (CI and VM) — no additional secret manager needed.
- Each dlt pipeline becomes a `@dlt_assets` Dagster asset with full lineage, runs, and materialization history in the UI.
- Incremental loading via `dlt.sources.incremental` covers the BigQuery → Snowflake flow without custom state management.

### Negative / Trade-offs

- Smaller connector catalog than Airbyte (~100 sources vs 500+). For this project the impact is nil (single BigQuery source), but it would matter on a multi-source setup.
- Less mainstream than Airbyte or Fivetran — I am betting on a smaller ecosystem.
- Operational experience with dlt at scale is thinner in the broader community than with Airbyte OSS.

### Risk Mitigations

- For sources not in dlt's catalog, dlt supports arbitrary Python generators — custom connectors remain straightforward.
- I reviewed dlt's issue tracker and release cadence before committing; the project is actively maintained.

## References

- [dlt documentation](https://dlthub.com/docs)
- [dlt + Dagster integration](https://dlthub.com/docs/dlt-ecosystem/visualizations/dagster)
- [Airbyte OSS deployment requirements](https://docs.airbyte.com/deploying-airbyte/)
