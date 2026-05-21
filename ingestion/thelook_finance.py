"""Finance pipeline: BigQuery `thelook_ecommerce` -> Snowflake `RAW.THELOOK`.

Scope: the 4 Finance-relevant tables. Two ingestion strategies, chosen per
table according to its semantic role:

  - Dimensions (`users`, `products`) -> `write_disposition='replace'`.
    Full-refresh on every run. No cursor, no cutoff. Dimensions must be
    complete (a fact row referencing a user from 2020 needs that user in
    dim_users — cutting them creates orphan foreign keys downstream).

  - Event streams (`orders`, `order_items`) -> `write_disposition='merge'`
    with `dlt.sources.incremental` on `created_at`, cut-off 2023-01-01.
    Cheap-to-replay incremental for transactional volumes.

The cutoff applies ONLY to the event-stream resources. The dimension
resources are loaded in full.
"""

from collections.abc import Iterator
from datetime import UTC, datetime
from typing import Any

import dlt
from google.cloud import bigquery

PIPELINE_NAME = "thelook_finance"
DATASET_NAME = "thelook"  # Snowflake schema -> RAW.THELOOK
CUTOFF = datetime(2023, 1, 1, tzinfo=UTC)


# ─────────────────────────────────────────────────────────────
# Dimensions (full-refresh, no cursor)
# ─────────────────────────────────────────────────────────────


@dlt.resource(
    name="users",
    write_disposition="replace",
    primary_key="id",
)
def users() -> Iterator[dict[str, Any]]:
    """Full-refresh loader for `bigquery-public-data.thelook_ecommerce.users`.

    Design decision (PR fix(ingestion): remove cutoff on users dimension) —
    `write_disposition='replace'` (full-refresh on every run), no incremental
    cursor, no cutoff. Three reasons:

    1. Orphan-free downstream. Cutting users by `created_at >= 2023-01-01`
       (the previous strategy) excluded historical users. fct_order_items
       from 2023+ that referenced those historical users produced ~77k
       orphan foreign keys — surfaced by the dbt relationships test on
       fct_order_items.user_id -> dim_users.user_id.
    2. Small dimension. ~100k rows of customer data, < 20 MB transferred
       per run. Compute cost on Snowflake XS warehouse (INGESTION_WH) is
       negligible.
    3. Pattern consistency. Same strategy as `products` — both are stable
       dimensions that benefit from full-refresh. The cutoff applies only
       to event-stream resources (orders, order_items).
    """
    client = bigquery.Client()  # project read from GOOGLE_APPLICATION_CREDENTIALS
    query = """
        SELECT *
        FROM `bigquery-public-data.thelook_ecommerce.users`
        ORDER BY id
    """
    for row in client.query(query).result():
        yield dict(row)


@dlt.resource(
    name="products",
    write_disposition="replace",
    primary_key="id",
)
def products() -> Iterator[dict[str, Any]]:
    """Catalog table loader: `bigquery-public-data.thelook_ecommerce.products`.

    Design decision — `write_disposition="replace"` (full-refresh on every
    run) instead of the `merge` incremental pattern used by event-stream
    resources. Three reasons:

    1. No timestamp lineage. The TheLook `products` table has no `created_at`
       or `updated_at` column. There's no cursor to slice the dataset on.
    2. Small dimension. ~30k rows of catalog data, < 5 MB transferred per run.
       The compute cost on Snowflake XS warehouse (INGESTION_WH) is negligible.
    3. Semantics. A product catalog is a "state of the world" snapshot, not
       an event log. Replace cleanly reflects the latest catalog without
       carrying stale rows from previous loads.

    Alternative considered: `merge` on `id` with no cursor (full table scan
    every run, diff-and-upsert). Rejected — more expensive than `replace`
    on a ~30k row table with no observable updates in the public dataset.
    """
    client = bigquery.Client()
    query = """
        SELECT *
        FROM `bigquery-public-data.thelook_ecommerce.products`
        ORDER BY id
    """
    for row in client.query(query).result():
        yield dict(row)


# ─────────────────────────────────────────────────────────────
# Event-stream resources (incremental merge on created_at)
# ─────────────────────────────────────────────────────────────


@dlt.resource(
    name="orders",
    write_disposition="merge",
    primary_key="order_id",
)
def orders(
    created_at_incremental: dlt.sources.incremental[datetime] = dlt.sources.incremental(
        "created_at",
        initial_value=CUTOFF,
    ),
) -> Iterator[dict[str, Any]]:
    """Incremental loader for `bigquery-public-data.thelook_ecommerce.orders`.

    Cursor on `created_at`, merge on primary key `order_id`. NOTE: `orders`
    is the only table in TheLook that uses `order_id` as PK instead of `id`
    (the other tables use `id`). Order rows include status (Processing /
    Shipped / Complete / Cancelled / Returned), gender, num_of_item, plus
    event-stream timestamps (returned_at, shipped_at, delivered_at).
    """
    client = bigquery.Client()
    cutoff = created_at_incremental.last_value
    query = """
        SELECT *
        FROM `bigquery-public-data.thelook_ecommerce.orders`
        WHERE created_at >= @cutoff
        ORDER BY created_at
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("cutoff", "TIMESTAMP", cutoff),
        ],
    )
    for row in client.query(query, job_config=job_config).result():
        yield dict(row)


@dlt.resource(
    name="order_items",
    write_disposition="merge",
    primary_key="id",
)
def order_items(
    created_at_incremental: dlt.sources.incremental[datetime] = dlt.sources.incremental(
        "created_at",
        initial_value=CUTOFF,
    ),
) -> Iterator[dict[str, Any]]:
    """Incremental loader for `bigquery-public-data.thelook_ecommerce.order_items`.

    Grain: one row per (order, item) pair — the fine-grain table that
    Finance marts will aggregate over. Same incremental + merge strategy
    as `orders`, since order_items shares the `created_at` lineage.
    """
    client = bigquery.Client()
    cutoff = created_at_incremental.last_value
    query = """
        SELECT *
        FROM `bigquery-public-data.thelook_ecommerce.order_items`
        WHERE created_at >= @cutoff
        ORDER BY created_at
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("cutoff", "TIMESTAMP", cutoff),
        ],
    )
    for row in client.query(query, job_config=job_config).result():
        yield dict(row)


# ─────────────────────────────────────────────────────────────
# Pipeline orchestration
# ─────────────────────────────────────────────────────────────


def run_pipeline() -> dlt.common.pipeline.LoadInfo:
    """Build and run the Finance pipeline across all 4 resources.

    dlt parallelises resource extraction up to its `workers` config
    (default 8). The 4 resources write to 4 distinct tables in the same
    `RAW.THELOOK` Snowflake schema.
    """
    pipeline = dlt.pipeline(
        pipeline_name=PIPELINE_NAME,
        destination="snowflake",
        dataset_name=DATASET_NAME,
        progress="log",
    )
    return pipeline.run([users(), orders(), order_items(), products()])


if __name__ == "__main__":
    load_info = run_pipeline()
    print(load_info)
