# infra/docker

Docker Compose stack deployed on the OCI Always Free VM.

## Scope

This stack currently focuses on Jalon A.5: Metabase self-service BI on top
of the Cube semantic layer. Dagster orchestration (Jalon A.3) will be added
back in a follow-up PR when `orchestration/` code lands.

## Services

| Service | Image | Port (internal) | Public URL |
|---|---|---|---|
| Caddy | `caddy:2` | 80, 443 | reverse proxy + auto-TLS |
| Metabase | `metabase/metabase:v0.50.20` | 3000 | `https://${METABASE_DOMAIN}` |
| Postgres (Metabase metadata) | `postgres:16` | 5432 | not exposed |

## Setup

```bash
cp .env.example .env   # fill in METABASE_DOMAIN, ACME_EMAIL, DB credentials
docker compose up -d
docker compose logs -f caddy   # watch for Let's Encrypt issuance
```

## TLS

Caddy handles ACME certificate issuance automatically via Let's Encrypt
(HTTP-01 challenge on port 80, then redirect to 443). Two prerequisites
before bringing the stack up:

1. The DNS A record `${METABASE_DOMAIN}` must already resolve to the OCI
   VM's Reserved Public IP. The HTTP-01 challenge needs DNS to validate
   before the cert is issued.
2. Ports 80 and 443 must be open in the OCI security list (already done
   by `infra/terraform/oci/networking.tf`).

## Architecture

Only Caddy exposes ports to the host. Metabase and its metadata Postgres
sit on internal Docker networks reachable only through Caddy. Named
volumes (not bind mounts) for easier backup via rclone.
