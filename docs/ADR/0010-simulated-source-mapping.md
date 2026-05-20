# ADR-0010: Simulated source mapping for portfolio narrative

- **Status**: Accepted
- **Date**: 2026-05-19
- **Tags**: portfolio, narrative, dbt, sources

## Context and Problem Statement

My project's only physical data source is `bigquery-public-data.thelook_ecommerce` — a single public BigQuery dataset with 7 tables (`users`, `products`, `inventory_items`, `distribution_centers`, `orders`, `order_items`, `events`). All 7 tables land in a single Snowflake schema (`RAW.THELOOK`) via one dlt pipeline (`ingestion/thelook_finance.py`).

A realistic data architecture for a French DTC fashion scale-up would never have only one source. In practice, each business function is served by its own upstream system: a CDP for customer identity, a PIM for product attributes, a WMS for inventory, an ERP for masterdata, a commerce platform for orders, an analytics tracker for events.

This ADR records my choice: do I (i) keep the dbt staging structure as a single source `thelook` matching the physical reality, (ii) split into multiple logical sources to mirror a realistic French DTC stack, or (iii) actually build 6 distinct ingestion pipelines for full architectural realism?

## Decision Drivers

- **Portfolio defensibility**: I built this project as a job-application asset. The dbt layer is the most-scrutinised part of the codebase in interviews. A staging layer organised by realistic source systems is recognisable to French recruiters (Sézane, Vestiaire Collective, Le Slip Français use exactly this pattern).
- **dbt best-practices structure**: the official dbt structure guide (`how-we-structure`) prescribes one staging subfolder per source system. Following the pattern is more pedagogical than collapsing everything under one source.
- **Honesty to readers**: an inflated portfolio that pretends to ingest real Segment / Shopify data and gets caught in interview is far worse than transparent simulation. Every YAML source description I write must say "simulated via the public TheLook eCommerce dataset".
- **Single-operator scope**: building and maintaining 6 distinct dlt connectors (each with its own API contract, schedule, error handling) is unrealistic for me as a solo contributor. The marginal pedagogical value over a well-explained simulation is low.

## Considered Options

- **Option A — Single source `thelook`**: one `_thelook__sources.yml` declares 7 tables. `staging/thelook/` contains all `stg_thelook__<table>.sql`. Matches the physical reality 1-to-1.
- **Option B — Multi-source simulation**: 6 logical sources matching realistic French DTC systems (Segment, Akeneo, Reflex, NetSuite, Shopify Plus, Snowplow+GA4). Each gets its own `staging/<source>/` subfolder. Every YAML description explicitly states "simulated via the public TheLook eCommerce dataset".
- **Option C — Real multi-pipeline ingestion**: build 6 distinct dlt connectors (Segment, Akeneo, Reflex, NetSuite, Shopify, Snowplow), each with its own schedule, error handling, and RAW subschema (`RAW.SEGMENT`, `RAW.AKENEO`, etc.). Full architectural realism.

## Decision

I chose **Option B** (multi-source simulation), because it captures the pedagogical and portfolio value of a realistic French DTC architecture while staying within my single-operator scope. Option A collapses the narrative and loses the staging layer's structuring benefit. Option C is operationally untenable for me alone and offers diminishing returns over a transparent simulation.

The canonical mapping I locked in is:

| BigQuery table | dbt source name | Upstream system (narrative) | Why this system |
|---|---|---|---|
| `users` | `segment` | Segment CDP | Modern CDP standard for unified customer profile |
| `products` | `akeneo` | Akeneo PIM | French PIM editor (Nantes), used by Vente-Privée, Sézane, Petit Bateau |
| `inventory_items` | `reflex` | Reflex (Hardis Group) | French WMS leader, used by Sézane, Sephora, Promod, C&A |
| `distribution_centers` | `netsuite` | NetSuite (Oracle) | THE ERP for DTC scale-ups (Sézane, Le Slip Français) |
| `orders` + `order_items` | `shopify` | Shopify Plus | De-facto standard DTC commerce platform in France |
| `events` | `snowplow` | Snowplow + GA4 | Snowplow for owned behavioural data, GA4 for marketing reporting |

The transparency rule I follow is non-negotiable: every `_<source>__sources.yml` description must explicitly state that the data is simulated via the public TheLook dataset. No reader (or recruiter) should ever assume real upstream data without explicit context.

## Consequences

### Positive

- **My dbt staging structure follows the dbt best-practices guide**: one staging subfolder per source, file-naming convention `stg_<source>__<entity>.sql`. The pattern is portable to any future project of mine.
- **Interview defensibility**: the narrative reads as a believable French DTC architecture. Recruiters recognise Akeneo, Reflex, NetSuite, Shopify Plus, Snowplow as standard players in their market. I can rehearse the talking point ("I designed the dbt staging layer as if data came from a realistic French DTC stack: Segment for users, Akeneo for products, ...").
- **Future-proof**: if I ever pursue Option C (build real multi-source ingestion), only the ingestion layer changes. The dbt structure already maps the right shape and the dim/fct marts that consume it stay untouched.

### Negative / Trade-offs

- **Modest YAML overhead**: 6 source YAML files instead of one, each with its own subfolder. Minor maintenance cost on my side.
- **Requires verbal framing in interview**: I must explicitly state "this is a portfolio simulation, in production each source would have its own pipeline" when discussing the architecture. Pretending otherwise would risk my credibility loss when probed on the actual ingestion path.

### Risk Mitigations

- Every `_<source>__sources.yml` description includes the explicit disclaimer "simulated via the public `bigquery-public-data.thelook_ecommerce` dataset".
- The `README.md` Decision records section links to this ADR, so any reader exploring the repo can find my rationale.
- My choice is reviewable: if Option C becomes feasible in a later phase (extra contributors, grant funding, or simply a follow-up portfolio iteration), the dbt structure I built already maps to multi-pipeline ingestion without staging refactor.

## Pros and Cons of the Options

### Option A — Single source `thelook`

- Good: minimal YAML overhead, matches physical reality with zero impedance.
- Bad: collapses the entire dbt staging pedagogy (no per-source subfolder), no narrative for interview, harder to extend later if multi-source ingestion is ever pursued.

### Option B — Multi-source simulation (chosen)

- Good: aligned with dbt best-practices guide, defensible French-market narrative, future-proof to real multi-source ingestion, honest via explicit disclaimers.
- Bad: requires upfront mapping decision (this ADR), small YAML overhead, demands I frame the simulation explicitly in interviews.

### Option C — Real multi-pipeline ingestion

- Good: most realistic architecture, no simulation gap to explain.
- Bad: 6 distinct dlt connectors for me to build and maintain, multiplied by 6 schedules, error handling paths, and monitoring. Unrealistic for me as a single operator. Diminishing returns over Option B given that recruiters care more about my modelling discipline than about my connectors-as-art.

## References

- dbt structure guide: <https://docs.getdbt.com/best-practices/how-we-structure/1-guide-overview>
- TheLook eCommerce public dataset: <https://console.cloud.google.com/marketplace/product/bigquery-public-data/thelook-ecommerce>
- Akeneo PIM: <https://www.akeneo.com>
- Reflex (Hardis Group) WMS: <https://www.hardis-group.com/solutions-logistiques/reflex-wms>
- Segment CDP: <https://segment.com>
- Shopify Plus: <https://www.shopify.com/plus>
- Snowplow: <https://snowplow.io>
- NetSuite: <https://www.netsuite.com>
