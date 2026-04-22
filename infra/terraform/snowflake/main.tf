terraform {
  required_version = ">= 1.6"

  required_providers {
    snowflake = {
      # Official Snowflake-maintained provider (GA since v2.0.0).
      # Migrated from the former community `Snowflake-Labs/snowflake` namespace.
      # Docs: https://registry.terraform.io/providers/snowflakedb/snowflake/latest
      source  = "snowflakedb/snowflake"
      version = "~> 2.0"
    }
  }
}

provider "snowflake" {
  organization_name = var.snowflake_organization_name
  account_name      = var.snowflake_account_name
  user              = var.snowflake_user
  authenticator     = "SNOWFLAKE_JWT"
  private_key       = var.snowflake_private_key
  role              = var.snowflake_role
}
