

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

    





with rawdata as (

    

    

    with p as (
        select 0 as generated_number union all select 1
    ), unioned as (

    select

    
    p0.generated_number * power(2, 0)
     + 
    
    p1.generated_number * power(2, 1)
     + 
    
    p2.generated_number * power(2, 2)
     + 
    
    p3.generated_number * power(2, 3)
     + 
    
    p4.generated_number * power(2, 4)
     + 
    
    p5.generated_number * power(2, 5)
     + 
    
    p6.generated_number * power(2, 6)
     + 
    
    p7.generated_number * power(2, 7)
     + 
    
    p8.generated_number * power(2, 8)
     + 
    
    p9.generated_number * power(2, 9)
     + 
    
    p10.generated_number * power(2, 10)
    
    
    + 1
    as generated_number

    from

    
    p as p0
     cross join 
    
    p as p1
     cross join 
    
    p as p2
     cross join 
    
    p as p3
     cross join 
    
    p as p4
     cross join 
    
    p as p5
     cross join 
    
    p as p6
     cross join 
    
    p as p7
     cross join 
    
    p as p8
     cross join 
    
    p as p9
     cross join 
    
    p as p10
    
    

    )

    select *
    from unioned
    where generated_number <= 1967
    order by generated_number



),

all_periods as (

    select (
        

    dateadd(
        day,
        row_number() over (order by generated_number) - 1,
        cast('2023-01-01' as date)
        )


    ) as date_day
    from rawdata

),

filtered as (

    select *
    from all_periods
    where date_day <= dateadd(year, 2, current_date())

)

select * from filtered



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