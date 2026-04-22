# ─────────────────────────────────────────────────────────────
# Service users
# Key-pair authentication (RSA) is preferred over password auth for services.
# Generate one key pair per user once, store the private key as a secret in
# the relevant runtime (GitHub Actions, dlt, Dagster on OCI), and set the
# public key on the corresponding rsa_public_key attribute.
#
# To regenerate a key pair:
#   openssl genrsa -out rsa_key.p8 2048
#   openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
#   # Paste the contents of rsa_key.pub (without headers/footers) into the
#   # corresponding TF_VAR_*_public_key Terraform Cloud variable.
# ─────────────────────────────────────────────────────────────

variable "user_dlt_public_key" {
  description = "RSA public key (PEM, without headers/footers) for USER_DLT."
  type        = string
  default     = ""
}

variable "user_dbt_public_key" {
  description = "RSA public key (PEM, without headers/footers) for USER_DBT."
  type        = string
  default     = ""
}

variable "user_dagster_public_key" {
  description = "RSA public key (PEM, without headers/footers) for USER_DAGSTER."
  type        = string
  default     = ""
}

variable "user_cube_public_key" {
  description = "RSA public key (PEM, without headers/footers) for USER_CUBE."
  type        = string
  default     = ""
}

resource "snowflake_user" "dlt" {
  name              = "USER_DLT"
  comment           = "[${var.project_tag}] Service user for dlt ingestion pipelines."
  default_role      = snowflake_account_role.ingestion.name
  default_warehouse = snowflake_warehouse.ingestion.name
  rsa_public_key    = var.user_dlt_public_key
}

resource "snowflake_user" "dbt" {
  name              = "USER_DBT"
  comment           = "[${var.project_tag}] Service user for dbt CLI runs (local + CI)."
  default_role      = snowflake_account_role.transform.name
  default_warehouse = snowflake_warehouse.transform.name
  rsa_public_key    = var.user_dbt_public_key
}

resource "snowflake_user" "dagster" {
  name              = "USER_DAGSTER"
  comment           = "[${var.project_tag}] Service user for Dagster-orchestrated runs on the OCI VM."
  default_role      = snowflake_account_role.transform.name
  default_warehouse = snowflake_warehouse.transform.name
  rsa_public_key    = var.user_dagster_public_key
}

resource "snowflake_user" "cube" {
  name              = "USER_CUBE"
  comment           = "[${var.project_tag}] Service user for Cube Cloud semantic layer queries."
  default_role      = snowflake_account_role.analyst_finance.name
  default_warehouse = snowflake_warehouse.consumer.name
  rsa_public_key    = var.user_cube_public_key
}

# ─── Role → User assignments ───────────────────────────────

resource "snowflake_grant_account_role" "dlt_has_ingestion" {
  role_name = snowflake_account_role.ingestion.name
  user_name = snowflake_user.dlt.name
}

resource "snowflake_grant_account_role" "dbt_has_transform" {
  role_name = snowflake_account_role.transform.name
  user_name = snowflake_user.dbt.name
}

resource "snowflake_grant_account_role" "dagster_has_transform" {
  role_name = snowflake_account_role.transform.name
  user_name = snowflake_user.dagster.name
}

resource "snowflake_grant_account_role" "cube_has_analyst_finance" {
  role_name = snowflake_account_role.analyst_finance.name
  user_name = snowflake_user.cube.name
}

# TODO: grant ROLE_ANALYST_MARKETING and ROLE_ANALYST_OPS to USER_CUBE
# when Marketing and Ops cubes are added in later iterations.
