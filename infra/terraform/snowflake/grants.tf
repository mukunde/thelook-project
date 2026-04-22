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

# ─── Role → User assignments are declared in users.tf ───────
