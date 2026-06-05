# ADR-0011: Cube modeling conventions for the Finance domain

- **Status**: Accepted
- **Date**: 2026-06-05
- **Deciders**: Gaël Mukunde
- **Tags**: semantic-layer, cube, kimball, view-only, finance

## Context and Problem Statement

[ADR-0007](0007-semantic-layer-cube-cloud.md) settled the high-level choice of Cube Cloud as the semantic layer. What it did not specify: how I structure the Cube schemas on top of the dbt marts, what grain my cubes expose, what gets exposed to BI clients, and how I avoid duplicating metric definitions that already live in dbt. The Finance domain is the first domain to land (post-rebuild marts in `ANALYTICS.MARTS`), and the conventions I pick here will set the pattern for Marketing and Operations later.

The forces at play:

- I want the semantic layer to add value (measurable arbitration, single metric truth) without re-implementing the metric logic that dbt already encodes.
- The portfolio narrative needs a clean separation between the modeling layer (cubes) and the consumption layer (BI). Recruiters reading the Cube code should be able to point at "the canonical definition of `net_revenue`" without ambiguity.
- I have one developer (me) and a hard time budget. The conventions must be opinionated enough to remove decision overhead at every new measure I add.

## Decision Drivers

- Avoid duplicating metric logic between dbt and Cube (DRY across layers).
- Make Cube refactor-able without breaking BI clients (decoupling via views).
- Mirror the dbt Kimball model 1:1 so the lineage stays readable end-to-end.
- Keep the connection RBAC tight (least privilege via `USER_CUBE` + `ROLE_ANALYST_FINANCE`, no exposure to staging).
- Onboard the Finance MVP fast (4 canonical measures, one view).

## Considered Options

- **Option A**, Strict Kimball reflection + grain `fct_order_items` only + view-only exposure.
- **Option B**, Wide Fact pattern at semantic layer (denormalize dim attributes into the cube for one-stop querying).
- **Option C**, Multi-grain (expose `fct_order_items` AND `fct_orders` as separate cubes with cube-side joins).

## Decision

Chosen option: **"Option A"**, because it preserves the DRY guarantee (metrics defined once in dbt, propagated via Cube measures) and gives me a clean refactor seam (view-only exposure) for when the Finance schema evolves.

Concretely:

1. **Strict Kimball reflection**: each Cube cube maps 1:1 to a dbt mart table (`order_items` to `fct_order_items`, `orders` to `fct_orders`, `users` to `dim_users`, `products` to `dim_products`, `dates` to `dim_dates`). No remodeling at the Cube layer.
2. **Grain entry point**: `fct_order_items`. All Finance measures aggregate from this grain. Cube handles rollup to order-level, day-level, month-level via dynamic SQL generation, no pre-computed rollup table at the semantic layer.
3. **View-only exposure**: all cubes carry `public: false`. A single Cube view named `finance` exposes the 4 canonical measures plus a curated set of dimensions (time via `dim_dates`, geography via `dim_users`, product axes via `dim_products`, order status). BI clients (Metabase, Evidence) consume the view, never the underlying cubes.
4. **4 canonical Finance measures** (defined exactly once, in the `order_items` cube):
   - `net_revenue` = `SUM(net_revenue)` from `fct_order_items.net_revenue` (already encodes "0 when status='Returned'", so the Cube measure inherits the dbt definition by referencing the column).
   - `gross_margin_rate` = `SUM(gross_margin) / NULLIF(SUM(net_revenue), 0)`.
   - `financial_return_rate` = `SUM(CASE WHEN status='Returned' THEN sale_price END) / NULLIF(SUM(sale_price), 0)`.
   - `avg_order_value` = `SUM(net_revenue) / COUNT(DISTINCT order_id)`. Note: not a `type: avg` direct because the grain (`order_items`) differs from the desired denominator grain (orders).
5. **Connection**: `USER_CUBE` + `ROLE_ANALYST_FINANCE` + `CONSUMER_WH` + database `ANALYTICS` (default schema `MARTS`). No access to `STAGING` (which exposes pseudonymised PII columns that have no business at the semantic layer).

## Consequences

### Positive

- Lineage stays clean: a Finance metric on a Metabase dashboard traces back to a Cube view, then a Cube cube, then a dbt mart column, then a dbt staging model, then a `RAW.THELOOK` column, then a BigQuery source row. One source of truth per layer.
- Refactoring cubes (renaming, splitting, adding joins) does not require touching BI clients as long as the `finance` view's contract is preserved.
- The 4 measures are interview-quotable: "I define `net_revenue` once, in `fct_order_items.net_revenue`, and reference it from the Cube cube. Metabase queries the Cube view, never the raw column. The metric has exactly one place where it can drift."
- The view-only pattern is a defensible modern convention (Cube docs recommend it explicitly since 2023). Recruiters reading the code see immediately that I follow current best practice.

### Negative / Trade-offs

- I cannot expose `fct_orders` as a separate cube without violating Option A. If a future need surfaces (e.g., a measure that only makes sense at the order grain and that Cube cannot derive from `fct_order_items`), I will need to revisit the grain choice. Mitigation: at the MVP scale (4 measures, ~180k rows in `fct_order_items`), Cube's dynamic aggregation handles all current cases without performance concern.
- View-only adds a layer of indirection (view, cubes, mart). Slightly more cognitive overhead when debugging a measure value. Mitigation: Cube's lineage view in the playground exposes the underlying cube and SQL for any view query.

### Risk Mitigations

- Schema source parametrized via Cube env var (`CUBEJS_DB_SCHEMA`), so the same code can target `ANALYTICS.MARTS` (prod) or `ANALYTICS_DEV.dbt_gm_marts` (dev) without code change.
- All cubes carry `public: false` from day one. If a future view is accidentally created without the matching `public: true` declaration, BI clients will not see it (fail-closed).
- Periodic metric unicity check (deferred to Jalon A.5): a Python notebook that queries the same metric via Cube REST API, via direct dbt mart SQL, and via Snowflake direct, then asserts equality. CI artifact.

## Pros and Cons of the Options

### Option A (chosen): Strict Kimball reflection + single grain + view-only

- Good: DRY metric definitions (one place per metric, in dbt mart).
- Good: Refactor-safe (view contract decouples cubes from BI).
- Good: Mirrors dbt model 1:1, lineage trivially readable.
- Bad: Cannot expose `fct_orders` as a separate addressable cube. Order-grain-only measures (rare in this scope) would need a Cube-side trick.

### Option B: Wide Fact pattern at semantic layer

- Good: Single cube to query, no joins to remember from the BI side.
- Bad: Duplicates dim attribute logic in Cube (product_category, user_country, etc.). Drift risk: a dim attribute renamed in dbt would need a parallel rename in Cube.
- Bad: Conflicts with Kimball-strict choice made in the dbt marts. The semantic layer should reflect the model, not subvert it.

### Option C: Multi-grain with cube-side joins

- Good: More flexibility for future measures that fit one grain or the other.
- Bad: Risk of duplicating metric definitions (`net_revenue` defined at both grains, drift over time).
- Bad: BI clients face ambiguity: "which cube do I query for revenue at order grain?"
- Bad: Overkill for the MVP scope (4 measures, well-bounded).

## References

- [ADR-0007: Cube Cloud as the semantic layer](0007-semantic-layer-cube-cloud.md)
- [ADR-0010: Simulated source mapping](0010-simulated-source-mapping.md)
- [Cube docs: Views](https://cube.dev/docs/reference/data-model/view)
- [Cube docs: Best practices](https://cube.dev/docs/product/data-modeling/recipes)
- [Phase 1 closure report](../infrastructure-and-governance-phase-report.md) (RBAC matrix, `USER_CUBE` / `ROLE_ANALYST_FINANCE`)
