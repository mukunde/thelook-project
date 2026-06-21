# ADR-0014: Keep the semantic layer in Cube, not in Snowflake (Semantic Views and Cortex Analyst)

- **Status**: Accepted
- **Date**: 2026-06-20
- **Deciders**: Gaël Mukunde
- **Tags**: semantic-layer, cube, snowflake, cortex-analyst, lock-in, tco, agentic-analytics

## Context and Problem Statement

[ADR-0007](0007-semantic-layer-cube-cloud.md) chose Cube Cloud as the semantic layer, comparing it against the dbt Semantic Layer (MetricFlow), self-hosted Cube Core, LookML, and no semantic layer at all. At that time (April 2026) one option was not on the table: a **warehouse-native semantic layer**. Snowflake Semantic Views (the object that holds logical tables, dimensions, metrics, and relationships inside Snowflake) and Cortex Analyst (the managed text-to-SQL agent that reads them) have since matured into a credible "bring the semantic layer to the warehouse" pattern, actively promoted by Snowflake.

That pattern is now common enough that a reader of the project's published article ([The Anatomy of Self-Service Analytics You Can Actually Trust](https://gaelmukunde.dev/blog/anatomy-self-service-analytics)) or an interviewer will reasonably ask: why is the semantic layer a standalone tool (Cube) in front of Snowflake, rather than inside Snowflake itself? This ADR records the answer explicitly. It does not re-open the tool comparison of ADR-0007; it adds the single axis ADR-0007 did not weigh: the **placement** of the semantic layer, inside the warehouse versus in front of it.

The trigger is also strategic. The project's current direction is agentic analytics, an AI agent as a first-class consumer of the same governed metrics (see [ADR-0013](0013-ktx-context-layer-for-ai-agents.md)). Snowflake's pitch for Semantic Views is precisely that they become "the context for Cortex Analyst". So the placement question is now entangled with the project's core thesis and deserves a recorded decision rather than an implicit one.

## Decision Drivers

- **€0 TCO and demo-on-demand** ([ADR-0006](0006-single-analytic-engine-snowflake.md), [ADR-0009](0009-oci-payg-with-cost-guardrails.md)): no paid per-query service, and the layer can go cold between demos.
- **Single definition, no second semantic layer**: the project's whole thesis is one canonical definition per metric. A second place to define metrics is a drift surface, the exact failure the project argues against.
- **Portability and no vendor lock-in**: Code-First, open formats, the ability to change the warehouse without rewriting the metrics.
- **Multi-surface consumption**: the same metric must reach BI (Metabase), direct SQL, and an AI agent over MCP (KTX), not a single vendor's assistant.
- **Demonstrability and portfolio narrative**: the decision must be defensible and consistent with the published article.

## Considered Options

- **Option A**: Keep Cube as the single semantic layer in front of Snowflake (status quo, ADR-0007).
- **Option B**: Move the semantic layer into Snowflake Semantic Views, consumed by Cortex Analyst (warehouse-native).
- **Option C**: Hybrid, Snowflake Semantic Views for governance plus Cube downstream for multi-surface consumption (the "governance in the warehouse, Cube for APIs" pattern several large orgs adopt).

## Decision

Chosen option: **"Option A, keep Cube"**, because for this project's constraints Semantic Views add cost and a second definition surface without removing any limitation Cube has, while the warehouse-native benefits (native RBAC reuse, Cortex synergy) only pay off for an organisation that is all-in on paid Snowflake, which this project is deliberately not.

Three reasons are decisive here:

1. **The valuable half is paid.** Semantic Views as an object are free, but their reason to exist for this project, feeding Cortex Analyst's text-to-SQL, is a paid, credit-consuming Snowflake feature. That breaks the €0 TCO commitment (ADR-0006) and the demo-on-demand model (a warehouse that must stay warm to serve an assistant is no longer demo-on-demand). Adopting Semantic Views without Cortex leaves only a second definition store that Cube would have to read from, which is pure added complexity.
2. **It creates a second semantic layer.** Metrics are defined once today, in dbt, reflected in Cube ([ADR-0011](0011-cube-modeling-conventions-finance.md)). Putting definitions in Semantic Views too means either duplicating them (drift, the failure the article is built around) or making Cube a passthrough with no benefit. One canonical definition is the thesis, two is the anti-pattern.
3. **It trades portability for the lock-in the project explicitly avoids.** A warehouse-native semantic layer binds the metric definitions to Snowflake. The project's positioning (Code-First, open formats, multi-surface, the freedom to move the warehouse) is the opposite. Cube sits in front of the warehouse and exposes SQL, REST, and GraphQL to BI, notebooks, and an agent over MCP. That vendor-neutral, multi-surface consumption is the whole point of ADR-0007 and ADR-0013.

Option C (hybrid) deserves a fuller treatment, because its upside is real. Putting definitions in Semantic Views and exposing them through Cube downstream does buy the best of both worlds on paper: Snowflake enforces RBAC, row-level security, and masking centrally and natively, while Cube still provides the multi-surface APIs and caching. For a large organisation this is a coherent target architecture, and it is the one the industry is visibly converging toward.

It is rejected here for three reasons specific to this project, not to the pattern:

1. **Governance gains are only realised when there is governance load to relieve.** This project is single-operator, read-only, on synthetic data, with no tenants, no per-user row-level security, and no PII policies to enforce. The hybrid would relieve a burden that does not exist, so its central benefit is unexercisable while its costs are fully paid.
2. **The hybrid presupposes a sunk investment.** Organisations adopt it because they already own and pay for Snowflake governance and do not want to discard it. Greenfield and at €0, that premise is absent: there is nothing to preserve, so the compromise has no anchor.
3. **It doubles the definition surface for no consumer benefit.** Definitions would live in Semantic Views and be remodelled in Cube, two places to keep coherent, the very drift surface the project argues against, with the operational cost landing on one person. If the AI path also went through Cortex it would re-import the paid dependency; if it stayed on Cube plus KTX, Semantic Views would be governance-only, and the only marginal gain over Cube alone would be native RBAC reuse, which (see Risk Mitigations) is moot at this scope.

In short, the hybrid is the right answer at enterprise scale with real governance load and existing Snowflake spend, and the wrong answer for a greenfield, single-operator, €0, read-only portfolio that would pay all of its costs and realise none of its benefits.

## What Snowflake Semantic Views genuinely do better (honest counter-case)

This decision is contextual, not a claim that Cube wins everywhere. Semantic Views are the better choice when:

- The organisation is **all-in on Snowflake and already pays for it**: governance, RBAC, row-level security, and dynamic data masking are reused natively, with no second system to synchronise. This is a real weakness of any standalone layer, including Cube.
- **Cortex Analyst is the desired agent** and its per-query cost is acceptable: the semantic layer becoming the official context of the warehouse-native AI is a genuinely clean architecture.
- The team wants **the fewest moving parts inside a single platform**.

The broader threat is worth naming: warehouses (Snowflake, Databricks, BigQuery) are all absorbing the semantic layer, which is the principal long-term risk to standalone tools like Cube. The decision here is correct **for this project's constraints**, not a bet that standalone semantic layers win the market.

## Consequences

### Positive

- The single-definition thesis stays intact: one metric definition (dbt, reflected in Cube), no second store, no drift surface.
- €0 TCO and demo-on-demand are preserved: no paid per-query assistant, the layer can go cold between demos.
- Portability is preserved: the warehouse can change without rewriting metrics, and consumption stays multi-surface (BI, SQL, agent over MCP).
- The decision is now an explicit, defensible artifact consistent with the published article: the "why not Semantic Views" question has a recorded answer.

### Negative / Trade-offs

- No native reuse of Snowflake RBAC, RLS, and masking at the semantic layer: Cube is a separate authorization surface (mitigated below).
- No Cortex Analyst: the project's text-to-SQL path is the Cube plus KTX plus MCP chain, not the warehouse-native assistant.
- Betting on a standalone layer while the market trend is warehouse-absorption, a position to revisit if the project's context changes.

### Risk Mitigations

- The auth boundary to Snowflake is **Cube**, not the BI tool or the agent ([ADR-0012](0012-replace-evidence-with-metabase-oss.md), ADR-0013). Cube holds the only warehouse credentials, so "no native RBAC reuse" does not mean a weaker posture for this single-operator, read-only analytics scope. This mitigation has an explicit boundary: in a multi-tenant or per-user row-level-security context the argument flips, because Cube would then have to re-implement and continuously synchronise the access policies Snowflake enforces natively, and that synchronisation gap is exactly where a warehouse-native semantic layer wins. If the project ever served multiple tenants or enforced per-user data access, this ADR should be re-opened on that basis alone.
- **Revisit trigger documented**: if the project ever adopts a paid Snowflake tier, needs native RLS or masking, or wants Cortex Analyst specifically, re-open this ADR. Because the metric definitions live in dbt and Cube YAML in Git, a migration would be a re-expression of existing definitions, not a redesign.

## Pros and Cons of the Options

### Option A (chosen): Keep Cube
- Good: €0, demo-on-demand friendly, portable, multi-surface (SQL/REST/GraphQL, BI, agent over MCP), one definition, consistent with ADR-0007/0011/0013 and the published article.
- Bad: separate auth surface from Snowflake, no native RBAC/RLS reuse, exposed to the warehouse-absorbs-semantics trend.

### Option B (rejected): Snowflake Semantic Views plus Cortex Analyst
- Good: native governance reuse, clean warehouse-native AI context, fewest moving parts for an all-Snowflake shop.
- Bad: Cortex Analyst is paid and credit-consuming (breaks €0 and demo-on-demand), Snowflake lock-in, single-vendor consumption rather than multi-surface.

### Option C (rejected): Hybrid (Semantic Views for governance plus Cube for consumption)
- Good: the pattern some large orgs converge on, governance in-platform, Cube for APIs and caching.
- Bad: two semantic layers to keep coherent (drift surface), only justified when the org already pays for and owns Snowflake governance, gratuitous for a greenfield €0 project.

## References

- [ADR-0006: single analytic engine, Snowflake](0006-single-analytic-engine-snowflake.md) (cost discipline that disqualifies paid per-query services)
- [ADR-0007: Cube Cloud as the semantic layer](0007-semantic-layer-cube-cloud.md) (the tool decision this ADR extends with the placement axis)
- [ADR-0009: OCI PAYG with cost guardrails](0009-oci-payg-with-cost-guardrails.md) (the €0 posture)
- [ADR-0011: Cube modeling conventions for Finance](0011-cube-modeling-conventions-finance.md) (where the canonical metrics live)
- [ADR-0013: KTX context layer for AI agents](0013-ktx-context-layer-for-ai-agents.md) (the agent consumes Cube over MCP, not a warehouse-native assistant)
- Published article: "The Anatomy of Self-Service Analytics You Can Actually Trust" (https://gaelmukunde.dev/blog/anatomy-self-service-analytics)
- [Snowflake Cortex Analyst documentation](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst)
- [Snowflake Semantic Views documentation](https://docs.snowflake.com/en/user-guide/views-semantic/overview)
- [Cube SQL API documentation](https://cube.dev/docs/product/apis-integrations/sql-api)
