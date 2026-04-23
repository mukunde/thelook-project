# ─────────────────────────────────────────────────────────────
# Cost guardrails — Snowflake resource monitor
#
# Every warehouse in this module is wired to THELOOK_MONTHLY_BUDGET.
# Without this file, a runaway query or forgotten warehouse could silently
# drain Snowflake credits. With it, the account hard-stops at 10 credits
# per month (~€20 on the on-demand tier at current pricing — well within
# the project's €0–10 demo budget assumption).
#
# Notification cadence:
#   50% / 75% / 90% → email notify (early warnings)
#   100%            → SUSPEND (finish the in-flight query, then stop)
#   110%            → SUSPEND_IMMEDIATE (kill everything)
#
# At 110%, no further queries run until the next monthly window rolls over
# or an ACCOUNTADMIN manually raises the quota. This is the safety net of
# the safety net — a second circuit breaker after the 100% threshold.
# ─────────────────────────────────────────────────────────────

resource "snowflake_resource_monitor" "project_budget" {
  name            = "THELOOK_MONTHLY_BUDGET"
  credit_quota    = 10
  frequency       = "MONTHLY"
  start_timestamp = "IMMEDIATELY"

  notify_triggers           = [50, 75, 90]
  suspend_trigger           = 100
  suspend_immediate_trigger = 110

  # Uncomment once a real email is registered on the Snowflake user and
  # NOTIFICATION_INTEGRATION is set up. Notifications go to the Snowflake
  # UI regardless, so this is optional for the bootstrap.
  # notify_users = [var.snowflake_user]
}
