# ADR-0006: Snowflake as the single analytic engine

- **Status**: Accepted
- **Date**: 2026-04-20
- **Tags**: architecture, kiss, snowflake, scope

## Context and Problem Statement

The project has two obvious temptations to multiply analytical engines:

1. **DuckDB as a local development target** for dbt, to iterate without spending Snowflake credits or having Snowflake provisioned.
2. **Oracle Autonomous Database as a fallback**, OCI Always Free includes two ADB instances at 0 €, so mirroring the marts there would keep a queryable dataset alive even when Snowflake is destroyed.

Both ideas appear free and synergistic. Both would introduce significant hidden costs in maintenance, mental load, and architectural clarity. This ADR records the deliberate choice to run the project on a single analytical engine: **Snowflake**.

## Decision Drivers

- **KISS discipline**: every additional engine multiplies the maintenance matrix (macros, tests, adapter-specific SQL, CI paths).
- **dbt cross-adapter correctness is hard**: subtle SQL differences between Snowflake and DuckDB or ADB surface as bugs in production.
- **Architectural clarity**: one engine, one SQL dialect, one adapter, no ambiguity when describing the system or debugging it.
- **Demo-on-demand discipline**: a single engine is rebuilt and torn down in minutes; two engines double the operational surface.
- **Scope budget**: the initial delivery already covers two IaC providers, an OCI VM, a Docker Compose stack, and a full dbt + Cube + Evidence delivery. Adding a second analytical engine would push scope beyond what is reasonable for the first milestone.

## Considered Options

- **Snowflake only (strict)**: a single analytical engine for RAW, ANALYTICS, and ANALYTICS_DEV.
- **Snowflake + DuckDB as local dev target**: dbt `dev` target on DuckDB, `prod` target on Snowflake. Appears free but forces cross-adapter SQL.
- **Snowflake + Oracle ADB fallback mirror**: ADB hosts a copy of the marts, kept queryable when Snowflake is destroyed. Appears free but doubles ingestion and RBAC work.
- **Snowflake + Postgres analytical replica**: Postgres on the OCI VM as a cheap query target for Metabase. Same complexity without the Snowflake features.

## Decision

I chose **Snowflake only**. The project is mono-engine by design. DuckDB, ADB, and Postgres are excluded as analytical engines regardless of their zero monetary cost, because the non-monetary cost (complexity, dev/prod parity risk, CI matrix) outweighs the benefit at this stage.

## Consequences

### Positive

- **Single mental model**: one SQL dialect, one adapter, one set of tests, one macro portability concern, none, since there is only one target.
- **Simpler CI**: the state-based CI pattern (`dbt build --select state:modified+ --defer`, which rebuilds only modified models and their descendants while deferring unmodified ones to the prod schema) runs once against a single target, no multi-adapter matrix to maintain.
- **Demo-on-demand stays fast**: one `terraform apply` rebuilds the entire analytical surface.
- **Zero risk of dev/prod drift** caused by adapter differences, a real and frequent source of bugs in multi-engine dbt projects.

### Negative / Trade-offs

- **No free analytical fallback when Snowflake is destroyed**: between active periods, no one can run an ad-hoc SQL query against live data.
  - Mitigation: Metabase cached query results, Evidence static dashboards, and Dagster run history together cover the "platform unreachable" window. Enough is visible without needing a live query surface.
- **Cannot showcase cross-adapter dbt work in this project.**
  - Mitigation: I treat this as a deliberate scope constraint. Cross-adapter work fits better as a separate focused side-project.
- **Trial / credit management overhead** on the Snowflake side (rotating trials, or upgrading to a small paid plan once the 30-day trial expires).
  - Mitigation: I documented the demo-on-demand workflow with `terraform apply` and `terraform destroy` as the only operational actions.

### Risk Mitigations

- Expectations about live-query availability are set explicitly via the documented demo-on-demand policy, so no one opens a dashboard expecting 24/7 SQL access.
- Metabase dashboards keep their last-successful-query results cached, preserving visual continuity when Snowflake is down.
- If a future iteration of the project ever needs a second engine (e.g. to benchmark costs or showcase portability), a new ADR will supersede this one.

## Pros and Cons of the Options

### Snowflake only
- Good: one mental model, simple CI, clear architecture, demo-on-demand stays fast.
- Bad: no free live SQL when Snowflake is torn down.

### Snowflake + DuckDB (dev target)
- Good: free iteration, no Snowflake credit consumption during development.
- Bad: cross-adapter SQL correctness, macros must be portable, CI matrix doubles, dev/prod drift is a real operational risk.

### Snowflake + Oracle ADB (fallback mirror)
- Good: "free" always-on SQL when Snowflake is destroyed.
- Bad: doubles ingestion paths, doubles RBAC design, adds a third Terraform provider, doubles the operational surface.

### Snowflake + Postgres (OCI VM)
- Good: lightweight, collocated with Metabase.
- Bad: same complexity explosion as the other multi-engine options, without the benefits of a true analytical database.

## References

- [dbt adapter differences (community discussions)](https://discourse.getdbt.com/)
- ADR-0004 (Terraform for Snowflake), complementary decision that this ADR locks in scope
