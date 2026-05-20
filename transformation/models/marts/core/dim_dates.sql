{{
  config(
    materialized='table'
  )
}}

-- dim_dates: conformed date dimension. Synthetic — no upstream source.
-- Generated via dbt_utils.date_spine, then enriched with calendar
-- attributes commonly needed for BI (year, quarter, month, day_of_week,
-- year_month, year_quarter, is_weekend).
--
-- Date range: 2023-01-01 (project cutoff aligned with dlt's incremental
-- cursor) to current_date() + 2 years (forward-looking buffer for any
-- order shipped_at / delivered_at that might land in the near future).
-- Re-built on every dbt run so the end_date stays fresh.
--
-- Note on day_of_week: Snowflake DAYOFWEEK convention is 0 = Sunday,
-- 6 = Saturday. ISO convention (Monday = 1, Sunday = 7) is available
-- via DAYOFWEEK_ISO if you ever need it downstream.
--
-- See _core__models.yml for column documentation and tests.

with date_spine as (

    {{
        dbt_utils.date_spine(
            datepart="day",
            start_date="cast('2023-01-01' as date)",
            end_date="dateadd(year, 2, current_date())"
        )
    }}

),

with_components as (

    select
        date_day::date as date_day,

        -- Atomic components
        extract(year from date_day)::number as year,
        extract(quarter from date_day)::number as quarter,
        extract(month from date_day)::number as month,
        extract(day from date_day)::number as day,
        extract(dayofweek from date_day)::number as day_of_week,
        extract(dayofyear from date_day)::number as day_of_year

    from date_spine

),

final as (

    select
        date_day,
        year,
        quarter,
        month,
        day,
        day_of_week,
        day_of_year,

        -- Composite BI-friendly attributes
        to_char(date_day, 'YYYY-MM') as year_month,
        year::varchar || '-Q' || quarter::varchar as year_quarter,

        -- Behavioural flag
        case when day_of_week in (0, 6) then true else false end as is_weekend

    from with_components

)

select * from final
