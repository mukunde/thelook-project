

-- dim_products: conformed product dimension. One row per product (SKU).
-- Materialised as a TABLE because BI tools (Cube, Metabase, Evidence) query
-- this surface frequently and expect predictable performance.
--
-- Consumes stg_akeneo__products via ref(). One-to-one passthrough at the
-- first iteration — no joins, no enrichment yet (those will come with
-- dim_products SCD2, inventory-derived stock_status, etc.).
--
-- See _core__models.yml for column documentation and tests.

with products as (

    select * from ANALYTICS_DEV.dbt_gm_staging.stg_akeneo__products

),

final as (

    select
        ----------------------------------------------------------------
        -- 1. Primary key
        ----------------------------------------------------------------
        product_id,

        ----------------------------------------------------------------
        -- 2. Financials
        ----------------------------------------------------------------
        cost,
        retail_price,

        ----------------------------------------------------------------
        -- 3. Categorical attributes
        ----------------------------------------------------------------
        category,
        name,
        brand,
        department,
        sku,

        ----------------------------------------------------------------
        -- 4. Foreign key
        ----------------------------------------------------------------
        distribution_center_id,

        ----------------------------------------------------------------
        -- 5. Audit columns (regenerated here, NOT propagated from staging:
        --    same rationale as dim_users — staging is a view evaluated
        --    at query time).
        ----------------------------------------------------------------
        current_timestamp() as _loaded_at,
        '3a43a263-8f43-4219-9ca0-365314c3a2e6' as _dbt_invocation_id

    from products

)

select * from final