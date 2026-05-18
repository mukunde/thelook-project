# Ingestion — dlt pipelines

dlt pipelines that land the public BigQuery [`thelook_ecommerce`](https://console.cloud.google.com/marketplace/product/bigquery-public-data/thelook-ecommerce) dataset into Snowflake `RAW.THELOOK`. Sprint 1 covers `users` only; subsequent sprints extend to `orders`, `order_items`, `products`.

## Stack

- **Source**: `bigquery-public-data.thelook_ecommerce` (public dataset, billed to the calling GCP project).
- **Destination**: Snowflake `RAW.THELOOK` via `USER_DLT` + `ROLE_INGESTION`, key-pair auth.
- **Incremental cursor**: `created_at`, cut-off `2023-01-01`, primary key `id`, write disposition `merge`.

## First-run setup

1. **Install deps** (from the repo root):
   ```powershell
   uv sync
   ```
   This creates `.venv/` and installs the workspace (root tooling + this module's deps).

2. **Populate Snowflake credentials**:
   ```powershell
   Copy-Item ingestion/.dlt/secrets.toml.example ingestion/.dlt/secrets.toml
   ```
   Edit `ingestion/.dlt/secrets.toml`:
   - `host`: your Snowflake account identifier (visible in your Snowsight URL).
   - `private_key`: paste the full PEM content of the `USER_DLT` private key file (the `.p8` you generated during the Phase 1 bootstrap). Dump its content with:
     ```powershell
     Get-Content <path-to-USER_DLT-private-key>.p8 -Raw
     ```

3. **Set GCP credentials env var** (per session, or add to your shell profile):
   ```powershell
   $env:GOOGLE_APPLICATION_CREDENTIALS = "<path-to-your-gcp-service-account>.json"
   ```

## Run the pipeline

```powershell
cd ingestion && uv run python thelook_finance.py
```

Expected output: a `dlt.LoadInfo` summary showing one job for `users` completed successfully. The table `RAW.THELOOK.users` is created (or merged into) by the first run.

Verify in Snowflake:
```sql
SELECT COUNT(*) FROM RAW.THELOOK.users;
SELECT MIN(_dlt_load_id), MAX(_dlt_load_id) FROM RAW.THELOOK.users;
```

## Tests

```powershell
# Unit tests only (default):
uv run pytest ingestion

# Integration test (requires Snowflake + GCP credentials set up):
uv run pytest ingestion -m integration
```
