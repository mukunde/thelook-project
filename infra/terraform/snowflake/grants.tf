# ─────────────────────────────────────────────────────────────
# Grants
# Least-privilege access for each role. Kept in a single file so the full
# access matrix is reviewable at a glance.
#
# Resource reference:
# https://registry.terraform.io/providers/snowflakedb/snowflake/latest/docs/resources/grant_privileges_to_account_role
# https://registry.terraform.io/providers/snowflakedb/snowflake/latest/docs/resources/grant_account_role
# ─────────────────────────────────────────────────────────────

# ─── Warehouse usage ────────────────────────────────────────

resource "snowflake_grant_privileges_to_account_role" "ingestion_warehouse" {
  account_role_name = snowflake_account_role.ingestion.name
  privileges        = ["USAGE", "OPERATE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.ingestion.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "transform_warehouse" {
  account_role_name = snowflake_account_role.transform.name
  privileges        = ["USAGE", "OPERATE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.transform.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_finance_warehouse" {
  account_role_name = snowflake_account_role.analyst_finance.name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.consumer.name
  }
}

# TODO: grant CONSUMER_WH usage to ROLE_ANALYST_MARKETING and ROLE_ANALYST_OPS
# when Marketing and Ops marts are wired in later iterations.

# ─── Database access ────────────────────────────────────────

resource "snowflake_grant_privileges_to_account_role" "ingestion_raw" {
  account_role_name = snowflake_account_role.ingestion.name
  privileges        = ["USAGE", "CREATE SCHEMA"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.raw.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "transform_raw_read" {
  account_role_name = snowflake_account_role.transform.name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.raw.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "transform_analytics" {
  account_role_name = snowflake_account_role.transform.name
  privileges        = ["USAGE", "CREATE SCHEMA"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.analytics.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "transform_analytics_dev" {
  account_role_name = snowflake_account_role.transform.name
  privileges        = ["USAGE", "CREATE SCHEMA"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.analytics_dev.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_finance_analytics" {
  account_role_name = snowflake_account_role.analyst_finance.name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.analytics.name
  }
}

# ─── Schema-level grants on RAW.THELOOK (dlt landing zone) ──
# ROLE_INGESTION must be able to write (USAGE + CREATE TABLE / VIEW) into the
# pre-declared RAW.THELOOK schema. ROLE_TRANSFORM must be able to read it.
# Future grants on TABLES / VIEWS ensure dbt (ROLE_TRANSFORM) automatically
# picks up SELECT on any object dlt creates in this schema.

resource "snowflake_grant_privileges_to_account_role" "ingestion_raw_thelook_schema" {
  account_role_name = snowflake_account_role.ingestion.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW"]

  on_schema {
    schema_name = "\"${snowflake_database.raw.name}\".\"${snowflake_schema.raw_thelook.name}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "transform_raw_thelook_schema" {
  account_role_name = snowflake_account_role.transform.name
  privileges        = ["USAGE"]

  on_schema {
    schema_name = "\"${snowflake_database.raw.name}\".\"${snowflake_schema.raw_thelook.name}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "transform_raw_thelook_tables" {
  account_role_name = snowflake_account_role.transform.name
  privileges        = ["SELECT"]

  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "\"${snowflake_database.raw.name}\".\"${snowflake_schema.raw_thelook.name}\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "transform_raw_thelook_views" {
  account_role_name = snowflake_account_role.transform.name
  privileges        = ["SELECT"]

  on_schema_object {
    future {
      object_type_plural = "VIEWS"
      in_schema          = "\"${snowflake_database.raw.name}\".\"${snowflake_schema.raw_thelook.name}\""
    }
  }
}

# ─── Schema & future-object grants on the Finance marts ─────

resource "snowflake_grant_privileges_to_account_role" "analyst_finance_marts_schema" {
  account_role_name = snowflake_account_role.analyst_finance.name
  privileges        = ["USAGE"]

  on_schema {
    schema_name = "\"${snowflake_database.analytics.name}\".\"${snowflake_schema.analytics_marts.name}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_finance_marts_tables" {
  account_role_name = snowflake_account_role.analyst_finance.name
  privileges        = ["SELECT"]

  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "\"${snowflake_database.analytics.name}\".\"${snowflake_schema.analytics_marts.name}\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_finance_marts_views" {
  account_role_name = snowflake_account_role.analyst_finance.name
  privileges        = ["SELECT"]

  on_schema_object {
    future {
      object_type_plural = "VIEWS"
      in_schema          = "\"${snowflake_database.analytics.name}\".\"${snowflake_schema.analytics_marts.name}\""
    }
  }
}

# TODO: replicate the three analyst_finance_marts_* blocks above for
# ROLE_ANALYST_MARKETING and ROLE_ANALYST_OPS when their marts are wired.

# ─── Role hierarchy (custom roles → SYSADMIN) ───────────────
# Snowflake best practice: every custom role inherits from SYSADMIN so that
# SYSADMIN (and ACCOUNTADMIN, which inherits from SYSADMIN) sees and manages
# every object the custom roles own. Without this chain, objects created by
# ROLE_INGESTION (e.g. RAW.THELOOK.users populated by dlt) are invisible to
# SYSADMIN and ACCOUNTADMIN — even break-glass actions on those objects fail
# without a temporary `GRANT ROLE x TO USER admin` first.
#
# Reference: https://docs.snowflake.com/en/user-guide/security-access-control-considerations
# (section "Aligning Object Access with Business Functions").

resource "snowflake_grant_account_role" "ingestion_to_sysadmin" {
  role_name        = snowflake_account_role.ingestion.name
  parent_role_name = "SYSADMIN"
}

resource "snowflake_grant_account_role" "transform_to_sysadmin" {
  role_name        = snowflake_account_role.transform.name
  parent_role_name = "SYSADMIN"
}

resource "snowflake_grant_account_role" "analyst_finance_to_sysadmin" {
  role_name        = snowflake_account_role.analyst_finance.name
  parent_role_name = "SYSADMIN"
}

resource "snowflake_grant_account_role" "analyst_marketing_to_sysadmin" {
  role_name        = snowflake_account_role.analyst_marketing.name
  parent_role_name = "SYSADMIN"
}

resource "snowflake_grant_account_role" "analyst_ops_to_sysadmin" {
  role_name        = snowflake_account_role.analyst_ops.name
  parent_role_name = "SYSADMIN"
}

# ─── Role → User assignments are declared in users.tf ───────
