# ADR-0003: BI layer — Evidence.dev + Metabase over Power BI / Tableau

- **Status**: Accepted
- **Date**: 2026-04-20
- **Tags**: bi, visualization, tco, public-hosting

## Context and Problem Statement

The project enforces a strict €0 TCO and a "demo-on-demand warehouse" discipline: Snowflake is destroyed between active periods, so consumption tools must either cache results gracefully or ship as static artefacts. Dashboards must also be openable by an external reader without an authentication gate — the friction of a login wall is unacceptable for a public-facing project.

Two complementary needs emerge:
1. A **static, always-available** dashboard that shows a data snapshot regardless of Snowflake state.
2. A **live dashboard** that proves the platform can serve interactive queries when Snowflake is up, and that caches queries gracefully when Snowflake is down.

## Decision Drivers

- **TCO €0** strict.
- **Public accessibility** without authentication friction.
- **Code-versioned BI** for the static artefact (CI/CD integration, PR review).
- **Live interactive BI** for the working surface.
- **No leakage of data models or credentials** (disqualifies "publish raw" tools like Tableau Public).
- **Hosting alignment**: the live BI should be hostable on the OCI VM to consolidate infrastructure.

## Considered Options

- **Power BI** (Pro / Premium) — industry standard, but public sharing requires Power BI Pro (~$10/month), incompatible with €0 TCO.
- **Tableau Public** — free, but publishing requires exposing the full data model publicly, an anti-pattern non-transposable to enterprise settings.
- **Tableau Cloud** — no permanent free tier.
- **Apache Superset** — rich BI, but self-hosting is heavy (multiple services, Celery, Redis).
- **Metabase** — Docker-hostable, straightforward, good default visualisations, public dashboards supported natively.
- **Evidence.dev** — Markdown + SQL, static site output, Vercel-deployable for free, code-versioned.
- **Streamlit** — Python-coded dashboards, flexible but feels more "app" than "BI".

## Decision

I chose **Evidence.dev for the static public dashboard + Metabase self-hosted on OCI for the live dashboard**. The two cover complementary needs (always-available static snapshot + live interactive queries) while preserving €0 TCO and alignment with the IaC / self-hosted strategy.

## Consequences

### Positive

- **Evidence.dev** dashboards are Markdown files committed to the repo — reviewable in PRs, regenerated in CI on every merge to `main`, and deployed to Vercel. A "Data snapshot: [date]" banner makes the demo-on-demand policy legible to visitors.
- **Metabase** runs on the OCI VM alongside Dagster. Its cached query results remain visible when Snowflake is destroyed; when Snowflake is up, dashboards are fully live.
- Strict €0 TCO preserved across both surfaces (Vercel Free for Evidence, OCI Free Tier for Metabase).

### Negative / Trade-offs

- Maintaining two BI surfaces is more work than a single tool would be.
- Evidence.dev is newer and less recognised than Power BI or Tableau.
- Metabase's visualisation depth is shallower than Power BI's for complex analytical reports.

### Risk Mitigations

- Evidence.dev's scope is deliberately narrowed to reporting and snapshots, not interactive exploration — playing to its strengths.
- Metabase dashboards focus on live operational metrics where its depth is sufficient; Evidence covers the reporting/snapshot use case.
- If Metabase on OCI ever becomes unstable, Evidence alone preserves the critical "always-on dashboard" asset.

## Pros and Cons of the Options

### Evidence.dev
- Good: code-versioned, CI/CD native, Vercel free deploy, works with demo-on-demand.
- Bad: newer ecosystem, no interactive drill-down as deep as Power BI.

### Metabase
- Good: quick to set up, public dashboards native, Docker-friendly, caches queries.
- Bad: visualisation library is adequate but not best-in-class.

### Power BI
- Good: industry standard, deep interactivity, rich formatting.
- Bad: paid for public sharing, closed ecosystem, not code-versionable natively.

### Tableau Public
- Good: free and well-known.
- Bad: exposes data model publicly — anti-pattern that cannot be defended in an enterprise setting.

## References

- [Evidence.dev documentation](https://evidence.dev/)
- [Metabase public dashboards](https://www.metabase.com/learn/administration/public-sharing)
