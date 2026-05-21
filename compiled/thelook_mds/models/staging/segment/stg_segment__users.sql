-- Staging model: Segment users -> snake_case, renamed, type-cast.
-- One row in = one row out (no aggregation, no filtering).
-- See _segment__models.yml for column documentation and tests.

with source as (

    select * from RAW.THELOOK.users

),

renamed as (

    select
        id::integer as user_id,
        ----------------------------------------------------------------
        -- PII columns: pseudonymised via SHA-256 + salt (macros/pseudonymise.sql).
        -- Salt is read from env var DBT_PSEUDONYMISATION_SALT at compile time.
        -- Output is a deterministic 64-char hex string (NULL preserved).
        ----------------------------------------------------------------
        
    sha2(concat(first_name, 'ci-docs-generation-dummy-never-executed'), 256)
 as first_name,
        
    sha2(concat(last_name, 'ci-docs-generation-dummy-never-executed'), 256)
 as last_name,
        
    sha2(concat(email, 'ci-docs-generation-dummy-never-executed'), 256)
 as email,
        
    sha2(concat(street_address, 'ci-docs-generation-dummy-never-executed'), 256)
 as street_address,
        ----------------------------------------------------------------
        -- Non-PII attributes
        ----------------------------------------------------------------
        age::integer as age,
        gender,
        state,
        postal_code,
        city,
        country,
        ----------------------------------------------------------------
        -- Geo-coordinates casted to ::float for explicit contract
        ----------------------------------------------------------------
        latitude::float as latitude,
        longitude::float as longitude,
        ----------------------------------------------------------------
        -- Acquisition
        ----------------------------------------------------------------
        traffic_source,

        ----------------------------------------------------------------
        -- Renamed timestamp to match business meaning
        ----------------------------------------------------------------
        created_at as registered_at,

        ----------------------------------------------------------------
        -- Audit columns appended by dbt
        ----------------------------------------------------------------
        current_timestamp() as _loaded_at,
        '3a43a263-8f43-4219-9ca0-365314c3a2e6' as _dbt_invocation_id

    from source

)

select * from renamed