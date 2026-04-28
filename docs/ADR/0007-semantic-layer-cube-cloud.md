# ADR-0007: Cube Cloud (Free / dev instance) as the semantic layer, over dbt Semantic Layer and self-hosted Cube Core

- **Status**: Accepted
- **Date**: 2026-04-21
- **Tags**: semantic-layer, metrics, cube, tco, demo-on-demand

## Context and Problem Statement

The project's core thesis is **metric uniqueness across departments**: Finance, Marketing and Operations must consume the exact same definitions of `net_revenue`, `conversion_rate`, `avg_order_value`, `gross_margin`, and return rate. dbt marts alone do not enforce this at consumption time, any downstream SQL can re-derive a KPI incorrectly (filter a return out, forget a partial refund, join on the wrong grain).

To make the uniqueness claim *provable*, the project exposes the same KPI definitions to **three heterogeneous consumers**, Metabase (live BI), Evidence.dev (static BI), and a Python notebook (`metric_unicity_check.ipynb`), and asserts that all three return identical numbers for every metric. This requires a **semantic layer** that:

1. Exposes a single canonical definition per metric.
2. Serves at least three different client types (SQL, REST, and/or GraphQL).
3. Fits the €0 TCO constraint and the demo-on-demand Snowflake policy.
4. Runs in CI so that Dagster asset checks can validate Cube ↔ dbt coherence.

The semantic layer is the component that makes "the same KPI everywhere" a verifiable property of the platform rather than a statement on a slide.

## Decision Drivers

- **Single definition, multi-consumer**: one model, three client types (SQL for Metabase, REST/GraphQL for the notebook, SQL for Evidence).
- **€0 TCO** strict, with tolerance for a dev-tier SaaS when it materially simplifies operations.
- **Minimal always-on surface**: the OCI Free Tier VM is already running Dagster, Metabase and Caddy; adding another always-on container is not free in operational terms.
- **Native dbt integration**: the semantic layer should read dbt models directly, without duplicating business logic.
- **Asset-check friendly**: Dagster must be able to query metric values via API to assert equality with dbt marts.
- **Demo-on-demand alignment**: when Snowflake is destroyed, the semantic layer can go cold, it does not need to serve live queries between demo windows.

## Considered Options

- **Cube Cloud Free (dev instance)**: managed SaaS, free dev tier, SQL + REST + GraphQL APIs, native Snowflake connector, cold start after inactivity.
- **Cube Core (self-hosted)**: same engine, deployed as a Docker container on the OCI VM. Free in licence, but consumes always-on VM resources.
- **dbt Semantic Layer (MetricFlow via dbt Cloud)**: metrics defined natively alongside dbt models, but the Semantic Layer API requires a paid dbt Cloud Team tier.
- **MetricFlow standalone**: open-source, CLI-oriented, no dedicated query API for heterogeneous BI consumers.
- **LookML (Looker)**: industry-standard semantic layer, paid, closed ecosystem.
- **No semantic layer**: rely on dbt marts only, duplicate KPI logic in Metabase, Evidence, and the notebook.

## Decision

I chose **Cube Cloud Free (dev instance)**. It is the only option that exposes a single metric definition to three heterogeneous consumers, stays strictly at €0, and keeps the always-on OCI VM footprint unchanged. The dev-tier cold start (~30 s) is acceptable given the demo-on-demand policy: the semantic layer is only exercised when Snowflake is provisioned, and a one-time 30 s warm-up at the start of a demo is a non-issue.

## Consequences

### Positive

- **Single source of metric truth**: `net_revenue`, `conversion_rate`, `avg_order_value`, `gross_margin`, and return rate are defined once in Cube schema files (versioned in the repo) and consumed identically by Metabase, Evidence, and the notebook.
- **Three consumer paths, one definition**: SQL API for Metabase and Evidence, REST/GraphQL for the notebook, all hitting the same compiled query plan against Snowflake.
- **Dagster asset check `cube_metrics_coherence`**: a custom check calls the Cube REST API for each KPI and compares the result to the equivalent dbt mart aggregate. Divergence fails the run, metric uniqueness becomes a CI-enforced invariant, not an aspiration.
- **Zero extra load on the OCI VM**: Cube Cloud runs as SaaS, preserving VM headroom for Dagster, Metabase, and Caddy.
- **Aligned with demo-on-demand**: Cube is idle between demos (its upstream warehouse does not exist); no attempt is made to keep it warm.

### Negative / Trade-offs

- **Cold start ~30 s** on the first query after inactivity. Documented in the README and in the demo playbook; the Loom video is recorded after a manual warm-up.
- **Dev tier only**: Semantic Layer Sync to BI tools (available on paid Cube Cloud tiers) is not used; the SQL API is the integration path for Metabase and Evidence. This is sufficient for the project's scope.
- **SaaS dependency**: the semantic layer is hosted outside the self-hosted OCI stack. If Cube Cloud's free tier changes, a migration to self-hosted Cube Core becomes necessary.
- **Lock-in to Cube's YAML/JS schema**: metric definitions are not portable to another semantic layer without rewriting.

### Risk Mitigations

- **Cube Core as an escape hatch**: Cube Core is the same engine, open-source, deployable on the OCI VM in under an hour. If the Cloud free tier is removed or restricted, migration is a packaging change, not a redesign. Metric definitions are unchanged.
- **Metric definitions live in the repo** (`cube/model/**.yml`), versioned and reviewable in PRs, not in a SaaS console. No vendor lock-in on the IP of the definitions themselves.
- **Cold-start expectation is documented**: the README, the Loom script, and the demo playbook all mention the 30 s warm-up so no reviewer interprets it as a broken pipeline.

## Pros and Cons of the Options

### Cube Cloud Free (dev)
- Good: €0, SaaS (no always-on VM load), SQL + REST + GraphQL out of the box, native Snowflake connector, metric definitions in the repo.
- Bad: cold start, dev-tier scope limits (no Semantic Layer Sync), SaaS dependency.

### Cube Core (self-hosted on OCI VM)
- Good: fully self-hosted, no SaaS dependency, identical feature set for metric definitions.
- Bad: adds another always-on container on the OCI Free Tier VM (Dagster + Metabase + Caddy are already co-located), operational burden for TLS / config / upgrades, no material benefit over Cloud Free at this project's scale.

### dbt Semantic Layer (MetricFlow via dbt Cloud)
- Good: metrics co-located with dbt models, single tool, best-in-class native integration with the transformation layer.
- Bad: the Semantic Layer API requires **dbt Cloud Team** (paid), incompatible with the €0 TCO constraint. Disqualified by ADR-0006's cost discipline.

### MetricFlow standalone
- Good: open-source, free, metric definitions close to dbt.
- Bad: no dedicated multi-protocol query API; wiring Metabase, Evidence, and a notebook to the same definition would require custom glue, defeats the "three consumers, one definition" proof.

### LookML (Looker)
- Good: mature, battle-tested semantic layer.
- Bad: paid, closed ecosystem, closed query language, not code-reviewable in a Git-native way. Out of scope for a public €0 project.

### No semantic layer
- Good: zero added tool, zero cold start.
- Bad: metric uniqueness becomes a prose claim rather than a CI-enforced property. Destroys the project's central thesis, not an option.

## References

- [Cube documentation](https://cube.dev/docs)
- [Cube Cloud pricing (free dev instance)](https://cube.dev/pricing)
- [dbt Semantic Layer availability](https://docs.getdbt.com/docs/use-dbt-semantic-layer/dbt-sl)
- ADR-0002 (Dagster OSS), the `cube_metrics_coherence` asset check is defined in the Dagster project.
- ADR-0003 (Evidence.dev + Metabase), the two BI consumers of the Cube SQL API.
- ADR-0006 (Snowflake only), the single warehouse that Cube is connected to.
