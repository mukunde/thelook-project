-- Staging model: Shopify orders -> snake_case, renamed, type-cast.
-- One row in = one row out. PK is order_id (TheLook particularity vs id elsewhere).
-- See _shopify__models.yml for column documentation and tests.

with source as (

    -- NO analytical horizon filter here. Reason: `orders` is a SUPPORTING
    -- ENTITY for the event-stream `order_items`. The analytical horizon
    -- (>= 2023-01-01) is enforced on order_items (the event stream the
    -- project actually analyses), but orders must remain complete so
    -- that items in early 2023 can resolve their FK back to orders
    -- late-finalised in late 2022. Filtering orders too would re-create
    -- the FK orphan pattern we just fixed. See stg_shopify__order_items
    -- for the analytical horizon filter, and portfolio TP-003 for the
    -- full diagnostic.
    select * from RAW.THELOOK.orders

),

renamed as (

    select
        ----------------------------------------------------------------
        -- 1. Primary key (PK is already order_id, cast for contract)
        ----------------------------------------------------------------
        order_id::integer as order_id,

        ----------------------------------------------------------------
        -- 2. Foreign key
        ----------------------------------------------------------------
        user_id::integer as user_id,

        ----------------------------------------------------------------
        -- 3. Status + lifecycle
        ----------------------------------------------------------------
        status,
        gender,
        num_of_item::integer as num_of_item,

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
        -- 6. Audit columns appended by dbt
        ----------------------------------------------------------------
        current_timestamp() as _loaded_at,
        '3a43a263-8f43-4219-9ca0-365314c3a2e6' as _dbt_invocation_id

    from source

)

select * from renamed