# infra/docker

Docker Compose stack deployed on the OCI Always Free VM.

## Services

| Service | Image | Port (internal) | Public URL |
|---|---|---|---|
| Dagster webserver | `ghcr.io/dagster-io/dagster:latest` | 3000 | `https://dagster.tondomaine.dev` |
| Dagster daemon | `ghcr.io/dagster-io/dagster:latest` | — | — |
| Metabase | `metabase/metabase:latest` | 3001 | `https://metabase.tondomaine.dev` |
| Postgres (Dagster) | `postgres:16-alpine` | 5432 | — |
| Postgres (Metabase) | `postgres:16-alpine` | 5433 | — |
| Caddy | `caddy:2-alpine` | 80, 443 | reverse proxy + auto-TLS |

## Setup

```bash
cp .env.example .env   # fill in DOMAIN, secrets, etc.
docker compose up -d
```

## TLS

Caddy handles ACME certificate issuance automatically via Let's Encrypt
(HTTP-01 challenge on port 80, then redirect to 443). Port 80 must be open
in the OCI security list (already done by `networking.tf`).

## Dagster workspace

`workspace.yaml` tells Dagster where to find code locations.
Add entries as ingestion / transformation / orchestration modules land.
