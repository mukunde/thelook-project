# Finance domain conventions

These rules govern every Finance analysis on the `finance` source. They
mirror ADR-0011 (Cube modeling conventions) and the dbt mart design; agents
must apply them without being asked.

## Canonical measures, single definition

Every Finance metric is defined ONCE at the order-item grain in the dbt mart
`fct_order_items`, propagated through the Cube view `finance`, and exposed
here as predefined measures. Always use the predefined measures rather than
recomputing your own aggregations:

- `total_net_revenue`: revenue actually kept. Returned items count as ZERO
  by construction (encoded in the dbt mart, not something to re-derive).
- `gross_margin_rate`: SUM(gross_margin) / SUM(net_revenue), computed on
  aggregated sums.
- `financial_return_rate`: SUM(returned_revenue) / SUM(gross_revenue).
- `avg_order_value`: SUM(net_revenue) / COUNT(DISTINCT order_id).

## Never average rate columns

The underlying Cube view also projects pre-computed rate columns. They are
hidden in this semantic layer ON PURPOSE: averaging rates across rows or
groups weighs a 1-euro order the same as a 1000-euro order and produces
wrong numbers. If a question needs a margin or return rate at any grouping,
use the predefined ratio measures, which recompose from additive sums.

## Returns: two different questions, two different rates

- "How much money do returns cost us?" is `financial_return_rate`
  (value-weighted, in euros). Its numerator uses the ORIGINAL sale_price of
  returned items, because their net_revenue is zero by construction (a
  net_revenue-based numerator would always be 0).
- "How often do customers return items?" is a VOLUME rate: returned item
  count over total item count. Compute it as a filtered `item_count` (via
  the `is_returned` dimension) over total `item_count`. Do not confuse the
  two; they can diverge widely when expensive items are returned more or
  less often than cheap ones.

## Status semantics

- `status` (line level) is the order line state; 'Returned' drives
  net_revenue zeroing.
- `orders_status` (order level) is the global order state (Complete,
  Cancelled, Processing...). An order can be Complete while one of its
  lines is Returned.

## Currency

All monetary values are in USD (TheLook dataset convention), even though
analyses are often phrased in euros in conversation. Do not convert; report
the unit as USD when precision matters.
