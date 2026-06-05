# semantic: Cube Cloud semantic layer (Finance domain)

The semantic layer over the dbt Finance marts. Defines 4 canonical Finance
measures once, exposes them via a single Cube view (`finance`) to BI clients
(Metabase, Evidence, ad-hoc Python notebooks).

See [ADR-0011](../docs/ADR/0011-cube-modeling-conventions-finance.md) for the
modeling conventions: Strict Kimball reflection, single grain `fct_order_items`,
view-only exposure, 4 canonical measures.

## Layout

```
semantic/
├── README.md              this file
├── pyproject.toml         uv workspace member stub
├── cube.js                Cube runtime config (schema discovery, env-driven connection)
├── .env.example           connection variables (local dev + Cube Cloud)
├── .gitignore
└── model/
    ├── cubes/             cube definitions (all `public: false` per ADR-0011)
    └── views/             `finance.yml` (the only public surface for BI clients)
```

## Connection

The Cube runtime authenticates as `USER_CUBE` against Snowflake, with the
`ROLE_ANALYST_FINANCE` role, the `CONSUMER_WH` warehouse, and reads from the
`ANALYTICS.MARTS` schema. The schema is overridable to
`ANALYTICS_DEV.dbt_<initials>_marts` for dev via `CUBEJS_DB_SCHEMA`.

The Snowflake objects (user, role, warehouse, schemas) are provisioned by
Phase 1 Terraform ([infra/terraform/snowflake/](../infra/terraform/snowflake/)).
The RBAC matrix is documented in the
[Phase 1 closure report](../docs/infrastructure-and-governance-phase-report.md).

## Deploying to Cube Cloud

Cube Cloud reads schema files from the connected Git repo.

1. In the Cube Cloud deployment: Settings -> Git -> Connect repository.
2. Select the repo and branch `main`, with `Project root path` set to
   `semantic/`.
3. Set the environment variables (same as `.env.example`) in
   Settings -> Configuration -> Environment Variables.
4. Cube Cloud auto-deploys on every push to the configured branch.

## Local dev (optional)

Cube Cloud is the primary runtime; the steps below are for offline iteration
on the schema files.

```bash
# 1. Copy the example env file and fill in real values (private key path, etc.).
cp .env.example .env

# 2. Run the Cube dev server via Docker.
docker run -p 4000:4000 \
  --env-file .env \
  -v "$PWD:/cube/conf" \
  cubejs/cube

# Playground at http://localhost:4000
```
