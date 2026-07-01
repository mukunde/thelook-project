# thelook-evals: offline evaluation harness

Offline evals for the analytics agent (Claude via the KTX context layer over MCP),
using `nao test`. Methodology and the validation-spike outcome are in ADR-0015 of the
main repo.

## How it works

Each test in `tests/*.yml` pairs a natural-language `prompt` with the canonical `sql`.
nao runs the agent to answer the prompt, executes the `sql` as an INDEPENDENT oracle
directly on `ANALYTICS.MARTS` (not through Cube or KTX), and compares the two result
sets to the cent. The agent reaches the data through the governed path
(KTX, Cube, Snowflake); the oracle is raw SQL on the marts. Agreement therefore
validates correctness, not merely internal consistency (the trap of TP-010, where four
agreeing surfaces were all wrong).

## Setup (local, one time)

```bash
# nao with the snowflake + anthropic extras (in its own uv tool env)
uv tool install --force 'nao-core[snowflake,anthropic]'

# copy the examples and fill in your local values
cp nao_config.yaml.example nao_config.yaml           # Anthropic key + Snowflake private-key path
cp agent/mcps/mcp.json.example agent/mcps/mcp.json   # KTX project dir
```

`nao_config.yaml` and `agent/mcps/mcp.json` are gitignored (they carry a secret and a
personal path). The oracle connects as `USER_CUBE` (read-only `ROLE_ANALYST_FINANCE`)
on `CONSUMER_WH`.

## Run

```bash
# 1. start KTX from the semantic-context project
ktx admin runtime start

# 2. start the nao backend (leave running); sign up once at http://localhost:5005
export KTX_PROJECT_DIR=<absolute-path-to>/semantic-context
nao chat

# 3. in another shell, run the eval against the local account and a CONCRETE model id
export NAO_USERNAME=<local-account-email>
export NAO_PASSWORD=<local-account-password>
nao test run --model anthropic:claude-sonnet-4-5-20250929
```

Notes:

- The model must be a concrete dated id; `-latest` aliases are rejected with a 500.
- The first run spins `CONSUMER_WH` from cold (~40s), so keep the set modest and warm
  the warehouse before a full run.

## Writing more tests

One `.yml` per question, one question per Finance rule from the KTX wiki:

- net revenue excludes returns (returns count as zero, by construction in the mart).
- value-weighted return rate uses the original `sale_price` of returned lines, since
  their net revenue is zero: `SUM(CASE WHEN status='Returned' THEN sale_price ELSE 0 END) / NULLIF(SUM(sale_price), 0)`.
- volume return rate is count-based and diverges from the value-weighted one.
- never average a rate: compute a margin from summed components, not from row-level rates.
- average order value is per distinct order, not per line.
- analytical horizon: data starts 2023-01-01, so a pre-2023 question returns nothing.

By-category questions join `dim_products` (confirm the category column name first):

```yaml
name: net_revenue_by_category
prompt: What is net revenue by product category?
sql: |
  SELECT p.category, SUM(f.net_revenue) AS net_revenue
  FROM ANALYTICS.MARTS.FCT_ORDER_ITEMS f
  JOIN ANALYTICS.MARTS.DIM_PRODUCTS p ON f.product_id = p.product_id
  GROUP BY p.category
  ORDER BY p.category
```
