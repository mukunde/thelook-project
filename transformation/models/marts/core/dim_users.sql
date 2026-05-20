{{
  config(
    materialized='table'
  )
}}

-- dim_users: conformed user dimension. One row per user.
-- Materialised as a TABLE (vs staging which is a VIEW) because BI tools
-- (Cube, Metabase, Evidence) query this surface frequently and expect
-- predictable performance.
--
-- Consumes stg_segment__users via ref() — dbt resolves the dependency at
-- compile time and guarantees stg_segment__users is built before this model.
--
-- PII (first_name, last_name, email, street_address) is already pseudonymised
-- at the staging layer (SHA-256 + salt). No plaintext PII lands here.
--
-- See _core__models.yml for column documentation and tests.

with users as (

    select * from {{ ref('stg_segment__users') }}

),

final as (

    select
        ----------------------------------------------------------------
        -- 1. Primary key (natural key from staging)
        ----------------------------------------------------------------
        user_id,

        ----------------------------------------------------------------
        -- 2. PII columns (pseudonymised at staging, passed through here)
        ----------------------------------------------------------------
        first_name,
        last_name,
        email,
        street_address,

        ----------------------------------------------------------------
        -- 3. Demographic attributes
        ----------------------------------------------------------------
        age,
        gender,

        ----------------------------------------------------------------
        -- 4. Geo attributes
        ----------------------------------------------------------------
        state,
        postal_code,
        city,
        country,
        latitude,
        longitude,

        ----------------------------------------------------------------
        -- 5. Acquisition
        ----------------------------------------------------------------
        traffic_source,

        ----------------------------------------------------------------
        -- 6. Business timestamp
        ----------------------------------------------------------------
        registered_at,

        ----------------------------------------------------------------
        -- 7. Audit columns (regenerated here, NOT propagated from staging:
        --    staging is a view evaluated at query time, so its audit cols
        --    are not a stable record of "when this row landed in the mart").
        ----------------------------------------------------------------
        current_timestamp() as _loaded_at,
        '{{ invocation_id }}' as _dbt_invocation_id

    from users

)

select * from final
