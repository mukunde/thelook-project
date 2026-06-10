# Analytical horizon: data starts on 2023-01-01

The analytical scope of this project begins on **2023-01-01**. This is a
deliberate design decision (the "analytical horizon" pattern), not a data
quality accident.

## What an agent must know

- Any query touching dates earlier than 2023-01-01 returns nothing by
  design. Do not interpret the absence of 2022 data as missing data or an
  ingestion failure.
- Year-over-year comparisons are only meaningful from 2024 onwards (2024 vs
  2023 is the first valid pair).
- The calendar dimension (`dates_*` columns) extends about two years into
  the future for delivery-date roll-ups; rows beyond today simply have no
  facts yet.

## Why (background)

The upstream storage layer (Snowflake RAW) actually ingests order events
from Q4 2022 onwards: order lines lag their parent orders by one to two
weeks, so ANY cutoff on the line-item stream creates orphaned references at
the boundary. Storage keeps a Q4 2022 buffer to absorb that tail, while the
analysis layer (dbt staging) filters event streams to the 2023-01-01
horizon. Supporting entities (users, products, orders headers) are kept
complete and unfiltered so that every line inside the horizon resolves its
references.

Net effect for analysis: ZERO orphaned foreign keys inside the horizon, and
a clean, stable baseline date for all Finance reporting.
