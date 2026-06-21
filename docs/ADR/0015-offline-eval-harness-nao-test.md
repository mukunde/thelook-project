# ADR-0015: Offline evaluation harness for the analytics agent (nao test), with a SQL oracle and ablation

- **Status**: Accepted (validation spike passed 2026-06-21)
- **Date**: 2026-06-20
- **Deciders**: Gaël Mukunde
- **Tags**: evals, agentic-analytics, nao, ktx, cube, testing, context-engineering

## Context and Problem Statement

The published article ([The Anatomy of Self-Service Analytics You Can Actually Trust](https://gaelmukunde.dev/blog/anatomy-self-service-analytics)) names two honest gaps: Layer 4 (procedural skills) and Layer 5 (validation and maintenance). Anthropic's method for both is eval-driven: a context piece is added only if it improves a measured accuracy score (skills moved their agent from 21% to over 95%, and accuracy drifted from 95% to 65% in a month without maintenance).

Two things follow. First, Layer 5 cannot be claimed without an offline evaluation harness that measures the agent's accuracy repeatably. Second, as recorded in [ADR-0014](0014-keep-semantic-layer-in-cube-not-snowflake-views.md), evals are the instrument that turns every future breadth decision (procedural skills, a knowledge graph, more context) into a measured choice rather than a guess. The harness is therefore both the next deliverable and the decision tool for everything after it.

This ADR records how the agent is evaluated. The agent under test is the existing one: Claude consuming the KTX context layer over MCP ([ADR-0013](0013-ktx-context-layer-for-ai-agents.md)), which queries Cube ([ADR-0007](0007-semantic-layer-cube-cloud.md)) over Snowflake.

## Decision Drivers

- **Measured, repeatable, offline**: accuracy as a number, not chat impressions.
- **Independent oracle**: ground truth must not come from the layer under test, otherwise the test only proves internal consistency, not correctness (the lesson of TP-010, four surfaces agreed and were all wrong).
- **€0 TCO and demo-on-demand**: a modest question count, a cached oracle, and awareness that each run spins warehouses (the 10-credit monitor still applies).
- **Reuse the existing agent**: evaluate Claude plus KTX, do not rebuild the context layer.
- **Ablation as the headline**: quantify each context piece's contribution, which is both the proof for the next blog deep-dive and the gate for future additions.
- **Code-First**: tests and configuration versioned in Git.

## Considered Options

- **Option A**: Adopt nao test (the open-source analytics-agent eval framework). YAML tests pair a natural-language prompt with the expected SQL; nao runs the agent, executes the SQL for ground truth, and compares the data.
- **Option B**: Bespoke Python harness (Anthropic SDK plus the KTX MCP server driven headless). Full control, more plumbing to build and maintain.
- **Option C**: A generic LLM-eval tool (for example promptfoo). Not analytics-aware, would require building the SQL execution and data-comparison layer anyway.

## Decision

Chosen option: **"Option A, nao test"**, because it is purpose-built for exactly this problem (text-to-SQL agents judged on data, not on prose or SQL string similarity), its model matches the independent-oracle requirement out of the box, and it consumes the existing agent through a standard MCP configuration rather than imposing a rebuild.

Architecture:

1. **Agent under test**: nao's agent runtime, configured to consume the existing **KTX MCP server** through nao's standard `agent/mcp/mcp.json` (the same MCP entry the desktop app already uses). KTX stays the context layer, nao adds only the runtime and the harness. This preserves the full KTX investment (ADR-0013).
2. **Oracle**: each test's expected `sql` is executed **directly on `ANALYTICS.MARTS`** (Snowflake), independent of Cube and KTX, by a read-only consumer role. The agent must reach the same number from a natural-language question using only the context layer.
3. **Comparison**: nao normalises both result sets to dataframes and compares exact-first, then approximate (relative tolerance 1e-5, absolute 1e-8). A test passes only when the data matches, not when the SQL looks similar.
4. **Question set**: roughly 15 to 25 Finance questions that encode the rules already written in the KTX wiki (returns excluded from net revenue, value-weighted vs volume return rate, the analytical horizon, never averaging a rate, average order value at the order grain).
5. **Ablation**: re-run the set with one context piece removed (for example hiding `analytical-horizon.md`, or re-exposing a pre-computed rate column) and measure the accuracy delta. This is the eval-driven proof and the gate for any future context addition.
6. **Location**: a new `evals/` module under the repo (its own nao project: `nao_config.yaml`, `agent/mcp/mcp.json`, `tests/`). nao is installed as a CLI tool via uv.

## Open questions to resolve in the validation spike

These are the unverified assumptions that justify the Proposed status. The spike runs one test end to end to answer them, after which this ADR is updated and flipped to Accepted.

1. Can nao's agent consume the **external KTX stdio MCP** through `agent/mcp/mcp.json` and actually use its tools to answer?
2. Which connection does nao use to execute the expected `sql`, and can it point at **Snowflake `ANALYTICS.MARTS`** directly (configured in `nao_config.yaml`)?
3. Does the agent answer through KTX, Cube, Snowflake (governed) while the oracle runs on the marts directly, and do the two match to the cent on a single test?
4. Does nao run more cleanly on Windows calling KTX over WSL, or inside WSL calling KTX directly? (the practical form of the MCP command).

## Validation spike outcome (2026-06-21)

One test (`total_net_revenue`) ran green end to end, answering all four questions and confirming the architecture:

1. **The agent uses KTX** (the critical one). The run logged 8 tool calls (`search`, `list`, `list`, `read`, `execute_sql` x4), the KTX toolset. With no nao-native context configured, a correct answer is only reachable through KTX, so this confirms KTX is the context source the agent reasons over.
2. **Snowflake oracle works**. nao connects to `ANALYTICS.MARTS` as `USER_CUBE` (key-pair, read-only `ROLE_ANALYST_FINANCE`) and executes the expected SQL for ground truth.
3. **Governed value equals the oracle to the cent**. The agent (Claude through KTX, Cube, Snowflake) returned net revenue 8,021,295.94 USD, matching the direct-SQL oracle on the marts: `match`. This is the full-history figure, consistent with the post-fix state in TP-010.
4. **Runtime**. nao runs fully in WSL, OSS mode (no `NAO_LICENSE`), spawning the KTX stdio MCP via `bash -c` with PATH and nvm sourced.

Gotchas worth recording (and good deep-dive material):

- nao test runs against a **local backend** (`nao chat`, FastAPI plus sqlite, OSS mode) behind a **local account** (sign up on `localhost:5005`, then pass `NAO_USERNAME` / `NAO_PASSWORD`). It is not a hosted-cloud gate: the agent executes locally with the local Anthropic key, the local KTX MCP, and the local Snowflake connection.
- The test runner's model is set per run with `--model provider:model_id` and is **independent of the `llm` block** in `nao_config.yaml`. It requires a **concrete model id** (a dated id such as `claude-sonnet-4-5-20250929`); `-latest` aliases were rejected with a 500.
- Cost was reported as $0 for that dated id (nao did not price it). Confirming per-test cost needs a priced model id or a nao update.
- A single run took about 40 seconds (cold `CONSUMER_WH` plus a multi-step agent loop), so the question set stays modest and the warehouse should be warmed before a full run.

Follow-ups before committing the eval project (PR2): ship a sanitised `nao_config.yaml.example` (the real one is gitignored, it carries the Anthropic key), and parameterise the personal paths (`private_key_path`, the KTX `--project-dir`) out of committed files.

## Consequences

### Positive

- Closes Layer 5 with a real, repeatable accuracy measurement, and gives the project the eval-driven decision instrument ADR-0014 relies on.
- Produces the ablation evidence that becomes the next blog deep-dive and justifies (or rejects) every future context addition with data.
- Preserves the existing agent and the full KTX context layer, nao is additive (runtime plus harness), not a replacement.
- Tests and configuration are versioned in Git, consistent with Code-First.

### Negative / Trade-offs

- A dependency on nao for the eval path, and on nao's support for an external MCP and a Snowflake connection (the spike de-risks this).
- Each run costs API tokens (the agent) and Snowflake compute (the agent path through Cube, plus the oracle queries), so it is not free to run often.
- The local KTX daemon must be running and healthy for a run (it has been fragile at startup, see ADR-0013 notes).
- LLM nondeterminism: the same question can phrase its answer differently. Handled by comparing the returned data, not the prose, and by keeping a numeric tolerance.

### Risk Mitigations

- **Read-only consumer for the oracle**: golden SQL runs under a read-only role on `ANALYTICS.MARTS` (the existing analyst role, or a dedicated `USER_EVAL` declared in Terraform), so the harness can never write.
- **Cost control**: keep the question count modest, cache the oracle results as fixtures so repeat runs do not re-query Snowflake for ground truth, and run during an active Snowflake window with the resource monitor in place.
- **Dedicated Anthropic API key** for the agent under test, so nao's per-test cost reporting is cleanly attributable.
- **Spike first**: validate the whole chain on one test before investing in the full question set and the ablation harness.

## Pros and Cons of the Options

### Option A (chosen): nao test
- Good: purpose-built for analytics agents, data-level comparison (catches SQL that is valid but semantically wrong), consumes the existing agent via standard MCP config, reports reliability, cost, latency, and tool-call count.
- Bad: a new dependency, and the external-MCP plus Snowflake-oracle wiring is documented thinly (resolved by the spike).

### Option B (rejected): bespoke Python harness
- Good: full control, no third-party coupling, fits the Python tactical default.
- Bad: re-implements what nao already does (agent invocation, SQL execution, dataframe comparison, reporting), more code to build and maintain for no differentiated benefit.

### Option C (rejected): generic LLM-eval tool
- Good: mature general-purpose eval tooling.
- Bad: not analytics-aware, would still need a custom SQL-execution and data-comparison layer, so it offers little over a bespoke harness for this use case.

## References

- [ADR-0007: Cube Cloud as the semantic layer](0007-semantic-layer-cube-cloud.md)
- [ADR-0011: Cube modeling conventions for Finance](0011-cube-modeling-conventions-finance.md)
- [ADR-0013: KTX context layer for AI agents](0013-ktx-context-layer-for-ai-agents.md) (the agent under test)
- [ADR-0014: semantic layer placement, Cube over Snowflake Semantic Views](0014-keep-semantic-layer-in-cube-not-snowflake-views.md) (establishes evals as the gate for breadth additions)
- Published article: [The Anatomy of Self-Service Analytics You Can Actually Trust](https://gaelmukunde.dev/blog/anatomy-self-service-analytics)
- [Anthropic: How Anthropic enables self-service data analytics with Claude](https://claude.com/blog/how-anthropic-enables-self-service-data-analytics-with-claude) (the eval-driven method)
- [nao test, evaluation documentation](https://docs.getnao.io/nao-agent/context-engineering/evaluation)
- [getnao/nao on GitHub](https://github.com/getnao/nao)
