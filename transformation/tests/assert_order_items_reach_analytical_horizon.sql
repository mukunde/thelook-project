-- Completeness guard (incident 2026-06-11, see TP-010 / ADR-0013 context):
-- after the Snowflake account rebuild, dlt resumed from a stale incremental
-- cursor and silently loaded only ~2 weeks of history instead of the full
-- analytical horizon. Every relationship/not_null/unique test stayed green,
-- because consistency tests hold within ANY time window.
--
-- This test asserts the history actually REACHES the analytical horizon
-- start (2023-01-01, see wiki + dbt staging filters): the earliest order
-- item must fall within the first week of the horizon. If dlt ever resumes
-- from a stale cursor again, this fails on the first dbt build.
--
-- Singular test: FAILS if any row is returned.

select min(ordered_at) as first_event_at
from {{ ref('stg_shopify__order_items') }}
having min(ordered_at) > '2023-01-08'::timestamp_tz
