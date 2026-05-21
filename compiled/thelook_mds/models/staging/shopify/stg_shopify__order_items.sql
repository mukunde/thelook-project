-- Staging model: Shopify order items -> snake_case, renamed, type-cast.
-- One row in = one row out. PK renamed from `id` to `order_item_id` to
-- disambiguate when joined with stg_shopify__orders and stg_akeneo__products.
-- See _shopify__models.yml for column documentation and tests.

with source as (

    -- Analytical horizon filter: the project analyses data from 2023-01-01
    -- onwards. Applied here because `order_items` is the event stream that
    -- drives every Finance fact downstream. RAW keeps a Q4 2022 buffer (see
    -- the ingestion pipeline's INCREMENTAL_BACKFILL_START rationale) so
    -- that items in early 2023 can still resolve their FK to orders
    -- late-finalised in late 2022 (kept in stg_shopify__orders without
    -- filter). The pattern: filter the EVENT STREAM, keep the SUPPORTING
    -- ENTITIES complete. See portfolio TP-003 for the full diagnostic.
    select * from RAW.THELOOK.order_items
    where created_at >= '2023-01-01'

),

renamed as (

    select
        ----------------------------------------------------------------
        -- 1. Primary key renamed: id -> order_item_id
        ----------------------------------------------------------------
        id::integer as order_item_id,

        ----------------------------------------------------------------
        -- 2. Foreign keys
        ----------------------------------------------------------------
        order_id::integer as order_id,
        user_id::integer as user_id,
        product_id::integer as product_id,
        inventory_item_id::integer as inventory_item_id,

        ----------------------------------------------------------------
        -- 3. Status + financials
        ----------------------------------------------------------------
        status,
        sale_price::float as sale_price,

        ----------------------------------------------------------------
        -- 4. Event timestamps (pass through, no rename)
        ----------------------------------------------------------------
        shipped_at,
        delivered_at,
        returned_at,

        ----------------------------------------------------------------
        -- 5. Renamed primary timestamp (business meaning)
        ----------------------------------------------------------------
        created_at as ordered_at,

        ----------------------------------------------------------------
        -- 6. Audit columns appended by dbt  done
        ----------------------------------------------------------------
        current_timestamp() as _loaded_at,
        '3a43a263-8f43-4219-9ca0-365314c3a2e6' as _dbt_invocation_id

    from source

)

select * from renamed