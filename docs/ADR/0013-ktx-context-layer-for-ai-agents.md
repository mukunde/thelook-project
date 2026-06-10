# ADR-0013: KTX context layer wrapping Cube for AI agent consumption

- **Status**: Accepted
- **Date**: 2026-06-10
- **Deciders**: Gaël Mukunde
- **Tags**: context-layer, ktx, mcp, ai-agents, semantic-layer, governance

## Context and Problem Statement

The Cube semantic layer ([ADR-0011](0011-cube-modeling-conventions-finance.md)) serves human BI well: Cube Explore for analysts, Metabase via the SQL API for end-users ([ADR-0012](0012-replace-evidence-with-metabase-oss.md)). The third consumer persona, AI agents, has different needs: it must discover what data exists, understand business rules that are not encoded in any schema (return-rate semantics, the analytical horizon, when NOT to average a rate), and execute queries deterministically instead of hallucinating SQL.

Cube's SQL and REST APIs are interfaces for tools, not for autonomous semantic navigation. The missing piece is a context layer: a system that ingests the technical schema, attaches human-authored business context, and exposes both to agents through the Model Context Protocol (MCP).

I evaluated KTX by Kaelio (open source, Apache 2.0), a context engine designed exactly for this gap.

## Decision Drivers

- Serve AI agents as a first-class consumer of the same canonical metrics that humans consume, without re-implementing metric logic
- Encode business knowledge (caveats, conventions, exceptions) where agents will actually read it
- Deterministic query execution: agents should select predefined measures, not generate free-form SQL
- €0 perpetual: open source, self-hosted, no gated trial
- Keep Cube as the single execution path and auth boundary to Snowflake

## Considered Options

- **Option A**: Cube's native MCP server only (no context layer)
- **Option B**: KTX wrapping Cube through the Cube SQL API (PostgreSQL protocol)
- **Option C**: KTX directly on Snowflake plus dbt, parallel to Cube

## Decision

Chosen option: **"Option B"**, KTX ingests the Cube SQL API as a PostgreSQL-compatible warehouse, so Cube remains the single execution path (security, caching, the canonical measures) while KTX adds what Cube does not have: wiki-based business context, semantic search across schema and docs, and a curated MCP surface with grain-aware query planning.

The two tools split responsibilities cleanly:

| Concern | Cube | KTX |
|---|---|---|
| Metric formulas, execution, caching | Owns | Delegates (generates SQL against Cube) |
| Snowflake credentials | Owns (auth boundary) | Never sees them |
| Business context in natural language | No support | wiki/ Markdown, embedded and searchable |
| Agent interface | SQL/REST (tool-oriented) | Native MCP with discovery, dictionary, predefined measures |

### Architecture

```
dbt (definitions) -> Snowflake -> Cube (semantic + execution)
                                    |-- Cube Explore (analysts)
                                    |-- SQL API -> Metabase (end-users)
                                    `-- SQL API -> KTX (context layer)
                                                     `-- MCP -> Claude / agents
```

### Implementation decisions (learned the hard way)

1. **Additive components over measure pass-through.** The KTX SQL parser accepts a closed list of aggregates (sum, avg, count, min, max, count_distinct, percentile, median); Cube's `MEASURE()` pseudo-aggregate is not parseable. Ratio measures therefore cannot delegate to Cube's ratio measures. Solution: the Cube view exposes the additive components (gross_revenue, gross_margin, returned_revenue, plus order_item_id and order_id), and KTX recomposes the ratios from those same canonical components (`sum(gross_margin) / nullif(sum(net_revenue), 0)`). The ratio formula exists in both layers, but always derived from the same additive columns defined once in dbt; the 4-surface cross-check guards against drift.

2. **Rate columns hidden on purpose.** The Cube view also projects pre-computed rate columns. Averaging them across rows or groups is the classic weighting error. The KTX overlay hides them (`visibility: hidden`) so agents are structurally forced through the predefined ratio measures. The visibility system then revealed a resolver behavior: manifest columns take precedence over same-named measures, so the KTX ratio measures carry distinct names (`gross_margin_ratio`, `financial_return_ratio`, `average_order_value`) with the BI-layer names documented in their descriptions.

3. **Scan snapshots are versioned, by design, with guardrails.** KTX batch-commits its scan snapshots (raw-sources/) to git; there is no opt-out flag, because reviewable context is the product's core contract. I initially gitignored those artifacts, which broke ingest, then adopted the tool's workflow with two guardrails: ingest runs only on feature branches (never on main; `storage.git.auto_commit` and `memory.auto_commit` are disabled for everything else), and `.gitattributes` marks the snapshots `linguist-generated` so GitHub collapses them in PR diffs.

4. **Wiki pages encode what no scan can know.** `wiki/global/finance-conventions.md` (never average rates, value-weighted vs volume return rates, status semantics, currency) and `wiki/global/analytical-horizon.md` (no data before 2023-01-01 by design, YoY valid from 2024). This is the layer that prevents an agent from producing a technically-correct, semantically-wrong answer.

5. **LLM and embedding providers.** Anthropic API key (dedicated, budget-capped) for enrichment agents rather than the Claude subscription: isolated quota, per-key tracking, no coupling to interactive usage. OpenAI text-embedding-3-small for semantic search after the local sentence-transformers runtime pulled ~2.5 GB of CUDA wheels on a GPU-less WSL2 host and hung on download retries; a $0.02/M-token API beat a multi-hour yak shave.

## Consequences

### Positive

- The metric-unicity demo now spans four surfaces: Cube Explore, Metabase, direct SQL, and an AI agent through KTX MCP, all returning identical values to the cent (net_revenue 492,930.60; Sweaters 2026-06 margin 51.98% on every surface).
- Agents inherit Cube's gating: the view-only contract (ADR-0011) is enforced once, in Cube, and every downstream consumer including KTX sees only what Cube exposes.
- Business rules live in versioned Markdown reviewed through PRs, satisfying the Code-First principle as refined in ADR-0012 (source of truth in git, consumption UI-driven or conversational).
- The whole layer is open source and self-hosted: no per-seat cost, no gated trial, aligned with the €0 TCO commitment.

### Negative / Trade-offs

- Ratio formulas are declared in two places (Cube measures for BI, KTX measures for agents), derived from the same additive components. Drift is possible in principle; the cross-surface validation query is the mitigation and should run after any change to either layer.
- Cube SQL API is not a complete PostgreSQL implementation (e.g. `ANY/ALL` with subqueries fails); KTX degrades gracefully but edge cases may surface as scans grow.
- KTX runs locally (WSL) for now: the MCP server serves the developer's own agents, not a shared endpoint. Promoting it to the OCI VM is deferred until a multi-consumer need exists.
- Scan snapshots add ~1 MB per scan to the repository. Accepted: scans only run on schema changes, from feature branches, with collapsed diffs.

### Risk Mitigations

- A change to canonical measures must update, in order: dbt mart, Cube cube/view, KTX overlay, then re-run the cross-surface check.
- KTX has no Snowflake credentials; a compromised context layer can read only what ROLE_ANALYST_FINANCE exposes through Cube.
- The Anthropic and OpenAI keys used by KTX are dedicated, stored in `.ktx/secrets/` (gitignored, verified absent from git history), and budget-alerted.

## References

- [ADR-0011: Cube modeling conventions](0011-cube-modeling-conventions-finance.md)
- [ADR-0012: Metabase over Evidence, Code-First scope refinement](0012-replace-evidence-with-metabase-oss.md)
- [KTX by Kaelio](https://github.com/Kaelio/ktx) (Apache 2.0)
- [Kaelio: building a context layer for the agentic era](https://www.kaelio.com/blog/building-a-context-layer-for-the-agentic-era)
- [Cube SQL API documentation](https://cube.dev/docs/product/apis-integrations/sql-api)
