{#
  Pseudonymise a PII column using SHA-256 with a project-wide salt.

  The salt is read from the env var DBT_PSEUDONYMISATION_SALT and must be set
  before any dbt run that touches PII columns. Each environment (dev / prod /
  CI) should use its own salt for blast-radius isolation in case of leak.

  Returns:
    - A deterministic 64-character hex string for non-null inputs.
    - NULL for null inputs (NULL is preserved naturally: in Snowflake
      CONCAT(NULL, anything) returns NULL, and SHA2(NULL, 256) returns NULL).

  Usage in a model:
    select
      {{ pseudonymise('email') }} as email,
      ...
    from {{ source('segment', 'users') }}

  Setup before first run (one-time):
    export DBT_PSEUDONYMISATION_SALT="$(openssl rand -base64 32)"
    # Persist in ~/.bashrc to survive shell restarts.

  Why pseudonymise rather than anonymise:
    - Pseudonymisation is deterministic (same input -> same hash), so PII
      columns can still be used as join keys (e.g. dim_users joined with
      external CRM exports on hashed email). Anonymisation would break joins.
    - The link to the natural person is preserved if the salt is known —
      this is the GDPR-aligned definition (art. 4(5)).
    - For full anonymisation, drop the salt and use a non-deterministic
      transform (e.g. random UUID per row), at the cost of join capability.

  References:
    - GDPR art. 4(5) on pseudonymisation: https://gdpr-info.eu/art-4-gdpr/
    - dbt env_var: https://docs.getdbt.com/reference/dbt-jinja-functions/env_var
    - Snowflake SHA2: https://docs.snowflake.com/en/sql-reference/functions/sha2
#}

{% macro pseudonymise(column_name) %}
    sha2(concat({{ column_name }}, '{{ env_var("DBT_PSEUDONYMISATION_SALT") }}'), 256)
{% endmacro %}
