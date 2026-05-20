-- Staging model: Segment users -> snake_case, renamed, type-cast.
-- One row in = one row out (no aggregation, no filtering).
-- See _segment__models.yml for column documentation and tests.

with source as (

    select * from {{ source('segment', 'users') }}

),

renamed as (

    select
        id::integer as user_id,
        ----------------------------------------------------------------
        -- PII columns: pseudonymised via SHA-256 + salt (macros/pseudonymise.sql).
        -- Salt is read from env var DBT_PSEUDONYMISATION_SALT at compile time.
        -- Output is a deterministic 64-char hex string (NULL preserved).
        ----------------------------------------------------------------
        {{ pseudonymise('first_name') }} as first_name,
        {{ pseudonymise('last_name') }} as last_name,
        {{ pseudonymise('email') }} as email,
        {{ pseudonymise('street_address') }} as street_address,
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
        '{{ invocation_id }}' as _dbt_invocation_id

    from source

)

select * from renamed
