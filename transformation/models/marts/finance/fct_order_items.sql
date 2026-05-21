{{
  config(
    materialized='table'
  )
}}

-- fct_order_items: order item-level fact table.
-- Grain: one row per (order, item) pair.
--
-- Joins stg_shopify__order_items with dim_products to enrich with `cost`
-- (needed for gross_margin). LEFT JOIN is used: if a product is missing
-- from dim_products (data quality issue), the row is kept with cost=NULL
-- and the downstream business calcs propagate NULL. This is the resilient
-- choice; a relationships test on product_id (deferred to a follow-up
-- feature) will surface any orphans.
--
-- Business metrics are computed in a dedicated `with_metrics` CTE so that
-- net_revenue is defined ONCE and referenced by name downstream (DRY).
-- gross_margin and gross_margin_rate in `final` reference net_revenue
-- directly, instead of repeating the case-when expression.
--
-- See _finance__models.yml for column documentation and tests.

with order_items as (

    select * from {{ ref('stg_shopify__order_items') }}

),

products as (

    select
        product_id,
        cost
    from {{ ref('dim_products') }}

),

joined as (

    select
        -- Identifiers + FK
        oi.order_item_id,
        oi.order_id,
        oi.user_id,
        oi.product_id,
        oi.inventory_item_id,
        oi.ordered_at::date as ordered_date,
        oi.delivered_at::date as delivered_date,

        -- Status + raw facts
        oi.status,
        oi.sale_price,
        p.cost,

        -- Event timestamps (passthrough)
        oi.ordered_at,
        oi.shipped_at,
        oi.delivered_at,
        oi.returned_at

    from order_items oi
    left join products p on oi.product_id = p.product_id

),

with_metrics as (

    -- net_revenue defined ONCE here. All downstream calcs that depend on it
    -- (gross_margin, gross_margin_rate) reference net_revenue by name in
    -- the `final` CTE below.
    select
        *,
        case when status = 'Returned' then 0 else sale_price end as net_revenue
    from joined

),

final as (

    select
        -- ─── Identifiers + FK ─────────────────────────────
        order_item_id,
        order_id,
        user_id,
        product_id,
        inventory_item_id,
        ordered_date,
        delivered_date,

        -- ─── Status + raw facts ───────────────────────────
        status,
        sale_price,
        cost,

        -- ─── Event timestamps ─────────────────────────────
        ordered_at,
        shipped_at,
        delivered_at,
        returned_at,

        ----------------------------------------------------------------
        -- ─── Business calculations ───────────────────────────────────
        ----------------------------------------------------------------

        -- 1. net_revenue (computed in with_metrics, passthrough here)
        net_revenue,

        -- 2. gross_margin = net_revenue - cost
        -- (NULL-safe: cost is NULL when the product is missing from
        -- dim_products, and NULL - X = NULL in Snowflake.)
        net_revenue - cost as gross_margin,

        -- 3. gross_margin_rate = gross_margin / net_revenue
        -- nullif(net_revenue, 0) protects against division by zero on
        -- returned items (where net_revenue = 0).
        (net_revenue - cost) / nullif(net_revenue, 0) as gross_margin_rate,

        -- 4. is_returned, is_delivered (BOOLEAN flags)
        case when status = 'Returned' then true else false end as is_returned,
        case when delivered_at is not null then true else false end as is_delivered,

        -- 5. days_to_delivery
        -- Snowflake DATEDIFF returns NULL naturally when delivered_at IS NULL.
        datediff(day, ordered_at, delivered_at) as days_to_delivery,

        ----------------------------------------------------------------
        -- ─── Audit columns ────────────────────────────────
        ----------------------------------------------------------------
        current_timestamp() as _loaded_at,
        '{{ invocation_id }}' as _dbt_invocation_id

    from with_metrics

)

select * from final
