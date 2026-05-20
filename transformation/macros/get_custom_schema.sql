{#
  Override of dbt's default generate_schema_name.

  Behavior:
    - In `prod` target:
        - custom_schema_name present -> use it as-is (e.g. `staging`, `marts`).
          Result: ANALYTICS.staging.stg_segment__users
        - custom_schema_name absent -> use the profile schema (e.g. `dbt_prod`).
    - In any other target (dev, ci):
        - custom_schema_name present -> prefix the profile schema to keep
          per-dev isolation AND classification visible.
          Result: ANALYTICS_DEV.dbt_gm_staging.stg_segment__users
        - custom_schema_name absent -> use the profile schema (e.g. `dbt_gm`).

  Note: this is similar to dbt's built-in `generate_schema_name_for_env`,
  but the built-in helper IGNORES `custom_schema_name` in non-prod targets
  (it returns just `target.schema`), which loses the staging/marts
  classification in dev. We want classification visible in dev too, so we
  expand the logic here.

  Reference:
    https://docs.getdbt.com/docs/build/custom-schemas
#}

{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}

    {%- if target.name == 'prod' -%}

        {%- if custom_schema_name is none -%}
            {{ default_schema }}
        {%- else -%}
            {{ custom_schema_name | trim }}
        {%- endif -%}

    {%- else -%}

        {%- if custom_schema_name is none -%}
            {{ default_schema }}
        {%- else -%}
            {{ default_schema }}_{{ custom_schema_name | trim }}
        {%- endif -%}

    {%- endif -%}

{%- endmacro %}
