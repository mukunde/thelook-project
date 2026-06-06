# ADR-0012: Replace Evidence with Metabase OSS, refine Code-First scope for self-service BI

- **Status**: Accepted
- **Date**: 2026-06-06
- **Deciders**: Gaël Mukunde
- **Tags**: bi, self-service, metabase, code-first, semantic-layer

## Context and Problem Statement

[ADR-0003](0003-bi-evidence-metabase-vs-power-bi.md) settled the original BI choice as Evidence.dev (static, Vercel-deployed) plus Metabase (live, OCI-hosted). At the time, the BI consumer was modelled implicitly as "the analytics team that produces dashboards and consumers who view them", fitting Evidence's developer-built-dashboards-as-code pattern naturally.

A live interview with a data leader at Jules (French menswear DTC) reframed the consumer persona I should actually be serving: **autonomise both analysts and end-users to minimise ad-hoc requests**. This is the canonical self-service analytics use case, where end-users point-and-click on safe semantic layer measures themselves rather than consume developer-built dashboards.

Evidence is not designed for this. Its strengths (Markdown-and-SQL files versioned in Git, deployed static) make it perfect for "developer-curated dashboards" but wrong for "end-user direct exploration on a semantic layer". I needed to re-evaluate the BI stack for the Jules-aligned brief.

I considered two modern semantic-layer-native BI tools (Omni, Hex) plus the original Evidence and Metabase options, before pivoting to Metabase OSS.

## Decision Drivers

- Serve the **two personas explicitly named in the Jules brief**: analyst (SQL/notebook flexibility) and end-user (point-and-click direct exploration on a curated semantic layer)
- Preserve the **Cube semantic layer as single source of metric truth** ([ADR-0011](0011-cube-modeling-conventions-finance.md)): BI consumers consume Cube views, do not bypass them
- **No paid subscription**: the portfolio €0 TCO commitment holds
- **Self-service signup**: avoid sales-gated trial paths that block iteration speed
- Preserve the **Code-First architecture principle** as much as possible without sacrificing the persona match

## Considered Options

- **Option A**: Keep Evidence plus Metabase (original ADR-0003)
- **Option B**: Pivot to Omni (modern Looker successor, semantic-layer-native)
- **Option C**: Pivot to Hex (modern data workbench, analyst-coded)
- **Option D**: Pivot to Metabase OSS on the already-provisioned OCI VM, drop Evidence

## Decision

Chosen option: **"Option D"**, because Metabase is the canonical self-service BI tool the persona expects, runs forever-free on the OCI infrastructure already in place, and consumes the Cube semantic layer via SQL API without re-implementing measures, while Omni and Hex turned out to be inaccessible for individual portfolio evaluators.

Concretely:

1. **Metabase OSS** is deployed via Docker Compose on the OCI A1 VM, with Caddy reverse-proxying TLS via Let's Encrypt. Reachable at `https://metabase.gaelmukunde.dev`.
2. **Connection to Cube**: Metabase connects to Cube Cloud's SQL API (PostgreSQL protocol). The Cube `finance` view appears as a virtual table; Metabase consumes the 4 canonical Finance measures (`net_revenue`, `gross_margin_rate`, `financial_return_rate`, `avg_order_value`) by their semantic-layer-defined names without re-implementing aggregation logic.
3. **Evidence dropped**: removed from the architecture diagram and from `docs/ADR/0003`. Its strengths do not serve the Jules persona, and including it for completeness would dilute the narrative.

## How I got to D, the access-friction finding (Omni and Hex)

I genuinely intended to evaluate Omni and Hex for their semantic-layer-native angle. The signup process revealed a pattern that informed the final choice:

- **Omni**: the "Free trial" CTA leads to a sales lead form ("Thank you, we'll be in touch"). For an individual portfolio evaluator without commercial context, the sales team has no incentive to grant access promptly.
- **Hex**: 14-day free trial is genuinely self-service, but the email filter rejected my custom-domain professional email (`gael@gaelmukunde.dev`) as a "non-business email" because the domain was registered roughly 2 hours before signup and had no reputation. The fallback "Request access" form was rejected too.

Insight: modern B2B BI tools' "free trial" pages are sales funnels, not portfolio-friendly evaluation channels. The pragmatic decision is to use the tool that unblocks the work (Metabase OSS, self-deploy), not the tool that wins the buzz contest. Captured separately in memory as a portfolio talking point.

## Code-First scope refinement

The previous interpretation of Code-First was absolute: every BI component declared as code under Git. Evidence served that narrative perfectly. Metabase does not, dashboards live in Metabase's metadata Postgres, not in version-controlled YAML files.

Refining the principle: **Code-First applies to the source of truth (the semantic layer), the consumption layer can be UI-driven for self-service democratization.** The metric definitions live in Git (Cube YAML plus dbt SQL); the way analysts and end-users explore them does not have to.

This refinement is more mature as a positioning. The dogmatic version (everything-as-code) blocks the very self-service use case the Jules-aligned employer wants to enable. The refined version says "the contract is in code, the consumption is human-friendly", which is industry-standard for analytics engineering teams.

## Consequences

### Positive

- The Cube semantic layer now feeds **three surfaces** with the same `finance` view and the same 4 canonical measures: Cube Cloud Explore (analyst-facing), Metabase (end-user-facing), and direct SQL on `ANALYTICS.MARTS.FCT_ORDER_ITEMS` (verification). The three surfaces return identical values to the cent (verified by cross-check on `net_revenue × products_category × dates_year_month` with `is_returned = false`). Single source of metric truth is visually demonstrable.
- Metabase is included in the portfolio narrative as the self-service surface that any French DTC AE recruiter recognises.
- The `docker compose` stack on the OCI VM serves a live, branded subdomain (`metabase.gaelmukunde.dev`) with auto-renewed Let's Encrypt TLS via Caddy. Always-on, €0 perpetual.
- The Code-First principle is now nuanced rather than absolute, defensible against the criticism "your stack does not allow the self-service the modern brief requires".

### Negative / Trade-offs

- Metabase's dashboards are not version-controlled the way Evidence's would have been. Loss of the "dashboards as code" narrative. Mitigation: documented as an explicit refinement of the Code-First principle (source of truth versioned, consumption layer not).
- Backup of Metabase's metadata Postgres is now a concern: if the OCI VM is destroyed, dashboards and users are lost unless backed up. Mitigation: the named Docker volumes will be rclone-backed-up to OCI Object Storage as part of Jalon C (Operations and Hardening); documented in `infra/docker/README.md`.
- The `latest` tag of Metabase image is used because Metabase ships ARM64 only under `latest` as of June 2026 (verified via `docker manifest inspect`). Trade-off documented inline in `docker-compose.yml` with a plan to pin to the SHA digest once the stack is stable enough.

### Risk Mitigations

- A dedicated `USER_METABASE` Snowflake user could be added via Terraform for stricter isolation, but the actual auth boundary to Snowflake is **Cube**, not Metabase. Metabase has no Snowflake credentials and could not bypass Cube even if compromised. The RBAC posture is already correct by architecture.
- Periodic backup of Metabase's metadata volume to OCI Object Storage to be added in Jalon C.

## Pros and Cons of the Options

### Option A (rejected): Keep Evidence plus Metabase

- Good: maximally aligned with original Code-First absolute interpretation.
- Bad: Evidence does not serve the end-user self-service persona the Jules brief defined. Adding it for completeness dilutes the narrative.

### Option B (rejected): Pivot to Omni

- Good: explicitly built for the persona (modern Looker, semantic-layer-native, end-user direct exploration).
- Bad: free trial is a sales lead form. Individual portfolio evaluator without commercial context is unqualified. Iteration speed incompatible with portfolio sprint.

### Option C (rejected): Pivot to Hex

- Good: strong analyst persona match (notebook plus data apps), AI-augmented exploration ("Hex Magic").
- Bad: email filter rejects custom-domain pro emails with no domain age. The end-user persona (point-and-click direct) is also less direct in Hex than in Omni or Metabase, the pattern is analyst-builds-apps-for-end-users.

### Option D (chosen): Metabase OSS on OCI

- Good: serves both personas, free perpetual, recognised industry, consumes Cube semantic layer via SQL API, no signup friction.
- Bad: dashboards not in Git (resolved via Code-First scope refinement above).

## References

- [ADR-0003: BI choice Evidence + Metabase over Power BI / Tableau](0003-bi-evidence-metabase-vs-power-bi.md) (Evidence portion superseded by this ADR)
- [ADR-0007: Cube Cloud as the semantic layer](0007-semantic-layer-cube-cloud.md)
- [ADR-0011: Cube modeling conventions for the Finance domain](0011-cube-modeling-conventions-finance.md)
- [Phase 1 closure report](../infrastructure-and-governance-phase-report.md) (OCI VM, Caddy, Docker stack infrastructure)
- [Metabase documentation: connecting to Postgres-compatible sources](https://www.metabase.com/docs/latest/databases/connections/postgresql)
- [Cube documentation: SQL API](https://cube.dev/docs/product/apis-integrations/sql-api)
