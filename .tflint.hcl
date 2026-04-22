# tflint root configuration — applied to all modules via --recursive
# Each module can override with its own .tflint.hcl.

config {
  # Call child modules (depth = 1 by default).
  call_module_type = "local"
}

# ── Provider plugins (none currently enabled) ───────────────
#
# Snowflake: the only public ruleset (chainguard-dev/tflint-ruleset-snowflake)
# was taken down and no active replacement exists on GitHub as of 2026-04.
# Terraform core rules below already catch naming, required versions, deprecated
# interpolations, etc. on Snowflake resources. Complementary security scanning
# is handled outside tflint (see tfsec / trivy in CI).
#
# OCI: no stable ruleset available. Re-enable here with a `plugin "oci"` block
# once one exists.
#
# Intentionally no `plugin` blocks here: declaring a plugin with `enabled = false`
# can still trigger a plugin resolution attempt in some tflint versions. Leaving
# the blocks out entirely is the safest way to avoid "Plugin not found" errors.

rule "terraform_deprecated_interpolation" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}
