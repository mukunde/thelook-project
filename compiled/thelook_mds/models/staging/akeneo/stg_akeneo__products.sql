-- Staging model: Akeneo products -> snake_case, renamed, type-cast.
-- One row in = one row out. PK renamed from `id` to `product_id`.
-- No timestamp rename (the source has no created_at/updated_at).
-- See _akeneo__models.yml for column documentation and tests.

with source as (

    select * from RAW.THELOOK.products

),

renamed as (

    select
        ----------------------------------------------------------------
        -- 1. Primary key renamed: id -> product_id
        ----------------------------------------------------------------
        id::integer as product_id,

        ----------------------------------------------------------------
        -- 2. Financials (cast to float for explicit contract)
        ----------------------------------------------------------------
        cost::float as cost,
        retail_price::float as retail_price,

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
        distribution_center_id::integer as distribution_center_id,

        ----------------------------------------------------------------
        -- 5. Audit columns appended by dbt  done
        ----------------------------------------------------------------
        current_timestamp() as _loaded_at,
        '3a43a263-8f43-4219-9ca0-365314c3a2e6' as _dbt_invocation_id

    from source

)

select * from renamed