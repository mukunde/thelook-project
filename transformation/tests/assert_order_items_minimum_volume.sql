-- Completeness guard, volume floor (companion to
-- assert_order_items_reach_analytical_horizon.sql, same incident).
--
-- The full analytical horizon holds ~150k order items as of 2026-06 and
-- only grows (TheLook generates data forward; the horizon start is fixed).
-- A count below 100k therefore always signals a partial load (stale
-- incremental cursor, truncated backfill), never a legitimate state.
--
-- Singular test: FAILS if any row is returned.

select count(*) as n_rows
from {{ ref('stg_shopify__order_items') }}
having count(*) < 100000
