-- Staging model: Shopify orders -> snake_case, renamed, type-cast.
-- One row in = one row out. PK is order_id (TheLook particularity vs id elsewhere).
-- See _shopify__models.yml for column documentation and tests.

with source as (

    select * from {{ source('shopify', 'orders') }}

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
        '{{ invocation_id }}' as _dbt_invocation_id

    from source

)

select * from renamed
