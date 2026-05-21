

-- fct_orders: order-level aggregated fact table.
-- Grain: one row per order.
--
-- This is a "fact-to-fact" model: it aggregates fct_order_items (sum / count
-- / avg of cleaned facts) rather than re-pulling from staging. By doing so,
-- it inherits the business logic already defined in fct_order_items (notably
-- the net_revenue case-when on Returned status). One canonical definition of
-- net_revenue, propagated by aggregation.
--
-- For order-level attributes (status, gender, event timestamps), we join
-- stg_shopify__orders directly — these don't come from item aggregation,
-- they're the order's own attributes.
--
-- CTE structure:
--   items                -> ref(fct_order_items)
--   orders_attributes    -> ref(stg_shopify__orders) (slimmed projection)
--   aggregated           -> GROUP BY order_id with SUM / COUNT / AVG
--   with_flags           -> derive boolean flags + rates from aggregated
--   joined               -> merge with_flags + orders_attributes
--   final                -> select + audit cols
--
-- The split aggregated / with_flags is deliberate: aggregated computes the
-- atomic aggregates; with_flags derives composed expressions (flags, rates).
-- More readable than inline lateral column aliasing.
--
-- See _finance__models.yml for column documentation and tests.

with items as (

    select * from ANALYTICS_DEV.dbt_gm_marts.fct_order_items

),

orders_attributes as (

    select
        order_id,
        user_id,
        status,
        gender,
        ordered_at,
        shipped_at,
        delivered_at,
        returned_at
    from ANALYTICS_DEV.dbt_gm_staging.stg_shopify__orders

),

aggregated as (

    -- GROUP BY order_id, compute atomic aggregates.
    select
        order_id,

        ----------------------------------------------------------------
        -- 1. items_count
        ----------------------------------------------------------------
        count(*) as items_count,

        ----------------------------------------------------------------
        -- 2. returned_items_count
        ----------------------------------------------------------------
        sum(case when is_returned then 1 else 0 end) as returned_items_count,

        ----------------------------------------------------------------
        -- 3. total_revenue_gross
        ----------------------------------------------------------------
        sum(sale_price) as total_revenue_gross,

        ----------------------------------------------------------------
        -- 4. total_revenue_net
        ----------------------------------------------------------------
        sum(net_revenue) as total_revenue_net,

        ----------------------------------------------------------------
        -- 5. total_cost
        ----------------------------------------------------------------
        sum(cost) as total_cost,

        ----------------------------------------------------------------
        -- 6. total_gross_margin
        ----------------------------------------------------------------
        sum(gross_margin) as total_gross_margin,

        ----------------------------------------------------------------
        -- 7. average_item_price
        ----------------------------------------------------------------
        avg(sale_price) as average_item_price

    from items
    group by order_id

),

with_flags as (

    -- Derive booleans + rates from the atomic aggregates above.
    -- Reference the aggregated columns by name (next-CTE pattern keeps
    -- this readable without lateral column aliasing).
    select
        *,

        ----------------------------------------------------------------
        -- 8. is_fully_returned
        -- BOOLEAN: TRUE if every item in the order was returned.
        ----------------------------------------------------------------
        items_count = returned_items_count as is_fully_returned,

        ----------------------------------------------------------------
        -- 9. is_partially_returned
        -- BOOLEAN: TRUE if some but not all items returned.
        ----------------------------------------------------------------
        returned_items_count > 0 and returned_items_count < items_count as is_partially_returned,

        ----------------------------------------------------------------
        -- 10. gross_margin_rate
        -- nullif protects against full-return orders where revenue = 0.
        ----------------------------------------------------------------
        total_gross_margin / nullif(total_revenue_net, 0) as gross_margin_rate

    from aggregated

),

joined as (

    -- Combine the aggregated metrics with the order-level attributes.
    -- INNER JOIN on order_id: every aggregated order must have a matching
    -- record in stg_shopify__orders (every order_item references a real
    -- order). If a mismatch arises, it's a data quality bug worth a
    -- relationships test on order_id -> stg_shopify__orders.
    select
        wf.order_id,
        oa.user_id,
        oa.ordered_at::date as ordered_date,
        oa.delivered_at::date as delivered_date,

        -- Order-level attributes
        oa.status,
        oa.gender,
        oa.ordered_at,
        oa.shipped_at,
        oa.delivered_at,
        oa.returned_at,

        -- Aggregated counts
        wf.items_count,
        wf.returned_items_count,

        -- Derived return flags
        wf.is_fully_returned,
        wf.is_partially_returned,

        -- Aggregated financials
        wf.total_revenue_gross,
        wf.total_revenue_net,
        wf.total_cost,
        wf.total_gross_margin,
        wf.gross_margin_rate,

        -- Aggregated averages
        wf.average_item_price

    from with_flags wf
    inner join orders_attributes oa on wf.order_id = oa.order_id

),

final as (

    select
        *,
        current_timestamp() as _loaded_at,
        '3a43a263-8f43-4219-9ca0-365314c3a2e6' as _dbt_invocation_id
    from joined

)

select * from final