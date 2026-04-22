# ADR-0002: Orchestration — Dagster OSS over Airflow

- **Status**: Accepted
- **Date**: 2026-04-20
- **Tags**: orchestration, python-first, dbt, lineage

## Context and Problem Statement

The project needs an orchestrator to schedule and coordinate the dlt → dbt → Cube pipeline, surface lineage, and run data quality checks across systems. The orchestrator is self-hosted on an OCI Always Free VM and must remain cheap to operate and Python-native to fit the rest of the stack.

The orchestrator is also the component that exposes the pipeline's operational state: anyone debugging a failed run or onboarding onto the project needs a single place to see lineage, run history, and check results without digging through scattered logs.

## Decision Drivers

- **Asset-oriented modelling**: dbt produces a graph of models; the orchestrator should represent this 1:1 without boilerplate translation.
- **Native dbt integration**: auto-generation of orchestration units from `manifest.json`, not an afterthought bolted on top.
- **UI quality**: lineage, runs, asset checks, and materializations must be legible at a glance rather than reconstructed from logs.
- **Python-native**: consistency with the dlt + notebook parts of the stack.
- **Data quality integration**: support for a third test layer beyond dbt tests, usable for cross-system checks (e.g. Cube ↔ dbt coherence).

## Considered Options

- **Airflow** (self-hosted, Astronomer, or MWAA) — industry standard, DAG-based, mature but task-oriented rather than asset-oriented, verbose dbt integration.
- **Dagster OSS** — asset-oriented, native dbt integration via `dagster-dbt`, modern UI, asset checks as a first-class concept.
- **Prefect** — similar philosophy to Dagster, weaker dbt integration.
- **GitHub Actions scheduled workflows only** — zero infrastructure, but no lineage, no UI, no asset checks.

## Decision

I chose **Dagster OSS**, self-hosted on the OCI VM. The asset-oriented model maps dbt one-to-one, `dagster-dbt` auto-generates assets from `manifest.json`, and the UI gives me a clear operational view of the pipeline — lineage, check results, and materialization history in one place.

## Consequences

### Positive

- Every dbt model becomes a software-defined asset with full lineage, metadata, and check history visible in the UI.
- Asset checks provide the third layer of the test strategy (cross-system coherence: Cube ↔ dbt ↔ Evidence) — a pattern I found hard to express cleanly in Airflow.
- The UI consolidates lineage graph, materialization timeline, asset check results, and run history — useful for debugging and for onboarding a second engineer later.
- Python-native code fits the dlt + dbt + notebook ecosystem without adapter layers.
- Dagster+ Cloud remains a natural option for a later iteration if operational load on the VM becomes inconvenient.

### Negative / Trade-offs

- Smaller community than Airflow; some advanced patterns (e.g. complex sensors) have fewer Stack Overflow answers.
- Steeper initial learning curve on Dagster-specific concepts (assets vs ops, IO managers, resources, partitions).
- Self-hosting Dagster means maintaining Postgres, the daemon, and the webserver as Docker services — an ops burden, partially offset by the single-VM Docker Compose setup.

### Risk Mitigations

- `dagster-dbt` removes most of the dbt-related boilerplate, so the learning curve applies only to Dagster-specific concepts, not to the dbt layer.
- Dagster documentation and examples are comprehensive; the project is well-funded and actively maintained.

## Pros and Cons of the Options

### Dagster OSS
- Good: asset-oriented, native dbt integration, modern UI, asset checks, Python-native.
- Bad: smaller community than Airflow, ops burden of self-hosting.

### Airflow
- Good: ubiquitous, vast community, battle-tested at very large scale.
- Bad: task-oriented (not asset-oriented), verbose dbt integration (Cosmos helps but adds a layer), UI less operationally legible for asset-centric workflows.

### GitHub Actions only
- Good: zero infrastructure, zero cost.
- Bad: no lineage, no asset model, no cross-system asset checks — eliminates the operational observability this project needs.

## References

- [Dagster software-defined assets](https://docs.dagster.io/concepts/assets/software-defined-assets)
- [dagster-dbt integration](https://docs.dagster.io/integrations/dbt)
- [Asset checks](https://docs.dagster.io/concepts/assets/asset-checks)
