"""Finance pipeline: BigQuery `thelook_ecommerce` -> Snowflake `RAW.THELOOK`.

Sprint 1 scope: `users` only. Subsequent sprints extend to `orders`,
`order_items`, and `products`. Cut-off and incremental cursor are decided
once here (FinOps + replay determinism) and reused by all Finance resources.
"""

from collections.abc import Iterator
from datetime import UTC, datetime
from typing import Any

import dlt
from google.cloud import bigquery

PIPELINE_NAME = "thelook_finance"
DATASET_NAME = "thelook"  # Snowflake schema -> RAW.THELOOK
CUTOFF = datetime(2023, 1, 1, tzinfo=UTC)


@dlt.resource(
    name="users",
    write_disposition="merge",
    primary_key="id",
)
def users(
    created_at_incremental: dlt.sources.incremental[datetime] = dlt.sources.incremental(
        "created_at",
        initial_value=CUTOFF,
    ),
) -> Iterator[dict[str, Any]]:
    """Incremental loader for `bigquery-public-data.thelook_ecommerce.users`.

    First run pulls every row with `created_at >= 2023-01-01`. Subsequent runs
    pull only `created_at > last_value`, where `last_value` is the maximum
    `created_at` seen on the previous run, persisted by dlt in its state.
    """
    client = bigquery.Client()  # project read from GOOGLE_APPLICATION_CREDENTIALS
    cutoff = created_at_incremental.last_value
    query = """
        SELECT *
        FROM `bigquery-public-data.thelook_ecommerce.users`
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


def run_pipeline() -> dlt.common.pipeline.LoadInfo:
    """Build and run the Finance pipeline. Returns the dlt LoadInfo summary."""
    pipeline = dlt.pipeline(
        pipeline_name=PIPELINE_NAME,
        destination="snowflake",
        dataset_name=DATASET_NAME,
        progress="log",
    )
    return pipeline.run(users())


if __name__ == "__main__":
    load_info = run_pipeline()
    print(load_info)
