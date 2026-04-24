# ADR-0008: Retain `admin_bootstrap` as a break-glass ACCOUNTADMIN with compensating controls

- **Status**: Accepted
- **Date**: 2026-04-24
- **Tags**: snowflake, rbac, security, break-glass

## Context and Problem Statement

Following ADR-0004 (Terraform for Snowflake), the initial Snowflake footprint was bootstrapped with a human user, let's call him `admin_bootstrap`, holding `ACCOUNTADMIN`. Terraform Cloud authenticated as this user for the first `apply`, which is an anti-pattern for steady-state operation: a human, interactively-usable, `ACCOUNTADMIN`-scoped identity should not be the day-to-day CI/CD principal.

A rotation was therefore performed:

- A custom role `ROLE_TERRAFORM` was created, inheriting `SYSADMIN` + `USERADMIN` + `SECURITYADMIN`, and granted direct ownership of the resource monitor `THELOOK_MONTHLY_BUDGET` (ADR-0004 already noted that `ACCOUNT MODIFY` does not exist in Snowflake and that resource-monitor management requires ownership).
- A service user `USER_TERRAFORM` was created with RSA key-pair authentication and `ROLE_TERRAFORM` as default role.
- Ownership of every module-managed object (3 warehouses, 3 databases, 3 schemas, 5 roles, 4 service users, 1 resource monitor) was transferred from `ACCOUNTADMIN` to `ROLE_TERRAFORM` with `OUTBOUND_PRIVILEGES = COPY`.
- Terraform Cloud workspace variables were rotated to the new service user and key pair; a subsequent `terraform plan` returned `0 to add, 0 to change, 0 to destroy`, confirming the rotation is clean.

The open question is what to do with `admin_bootstrap` now that `USER_TERRAFORM` is the canonical automation identity. The original plan in the `terraform_rbac.tf` header comment was to `ALTER USER admin_bootstrap SET DISABLED = TRUE`. In practice, attempting this returned `User cannot disable oneself`, and the broader question surfaced: does this portfolio project actually benefit from disabling it at all, and what is the right compensating-control posture if we keep it?

## Decision Drivers

- **Principle of least privilege**: the automation principal (`USER_TERRAFORM`) must not be `ACCOUNTADMIN`; that is non-negotiable and is already satisfied by the rotation above.
- **Break-glass availability**: Snowflake restricts certain operations (notably creating new resource monitors and some account-level modifications) to `ACCOUNTADMIN`. Losing access to any `ACCOUNTADMIN` identity would hard-block future platform changes and force an account-recovery procedure.
- **Attack surface**: a human, password-authenticated, `ACCOUNTADMIN`-scoped user is a high-value target. Every additional enabled identity with that scope widens the surface.
- **Project context**: this is a single-operator portfolio project on a Snowflake 30-day trial account. There is no multi-tenant blast radius, no customer data, and no production SLA.
- **Operational simplicity**: creating and maintaining a second dedicated break-glass user adds complexity (one more credential to rotate, one more password vault entry, one more documented procedure) for marginal security gain in this context.

## Considered Options

- **Option A — Disable `admin_bootstrap`.** Fully follow the original plan. Requires logging in as another `ACCOUNTADMIN` to perform the `DISABLE = TRUE`, which means creating a second break-glass user first or using Snowsight under another session.
- **Option B — Create a dedicated `USER_BREAK_GLASS` and disable `admin_bootstrap`.** Replace `admin_bootstrap` with a purpose-built, clearly-named break-glass identity (MFA, strong password, usage-logged), then disable `admin_bootstrap`.
- **Option C — Retain `admin_bootstrap` with compensating controls.** Keep the user as the break-glass identity, but apply mitigations: MFA, strong password, explicit "do-not-use-for-automation" documentation, and reliance on `USER_TERRAFORM` for all day-to-day operations.

## Decision

Chosen option: **Option C — retain `admin_bootstrap` with compensating controls**, because for a single-operator portfolio project the marginal security benefit of Option B does not justify the additional credential-management burden, and Option A is operationally risky without Option B's groundwork. The automation principal separation (the actual RBAC win) has already been achieved by the rotation to `USER_TERRAFORM`/`ROLE_TERRAFORM`; what remains is the break-glass question, which Option C addresses adequately in this context.

Concretely:

- `admin_bootstrap` stays enabled as the sole `ACCOUNTADMIN` interactive identity.
- `USER_TERRAFORM` (scoped to `ROLE_TERRAFORM`) is the only identity used by Terraform Cloud and by any CI/CD automation.
- The four service users (`USER_DLT`, `USER_DBT`, `USER_DAGSTER`, `USER_CUBE`) continue to use their least-privilege roles (`ROLE_INGESTION`, `ROLE_TRANSFORM`, etc.).
- `admin_bootstrap` is used only for operations that provably require `ACCOUNTADMIN` (e.g. creating a brand-new resource monitor), and the rationale is recorded in the commit or runbook each time.

## Scope of break-glass usage

To keep the "break-glass" qualifier operational rather than theoretical, the following lists define what is and what is not in scope for an `admin_bootstrap` session. The test to apply before every such session is: *"could this operation have been performed by merging a PR that triggers a Terraform Cloud apply as `USER_TERRAFORM`?"* — if yes, do it in a PR; if no, the operation is legitimately break-glass.

### In scope (legitimate break-glass operations)

- **Create a new `RESOURCE MONITOR`.** Snowflake restricts resource-monitor creation to `ACCOUNTADMIN`. `ROLE_TERRAFORM` can modify monitors it already owns (e.g. `THELOOK_MONTHLY_BUDGET`) but cannot create new ones. Adding a second monitor therefore requires a one-off apply as `admin_bootstrap`.
- **Recover from an ownership-divergence deadlock.** If a module-managed object has its ownership drift away from `ROLE_TERRAFORM` (partial apply failure, manual edit in Snowsight, state corruption), `ROLE_TERRAFORM` loses the right to manage it and cannot fix the situation itself. `ACCOUNTADMIN` is needed to re-transfer ownership — this is the scenario that produced the `GRANT ROLE ROLE_TERRAFORM TO ROLE ACCOUNTADMIN` escape-hatch used during the initial rotation.
- **Recover access to `USER_TERRAFORM`.** If the private key is lost, corrupted, or suspected compromised, only `ACCOUNTADMIN` can rotate `USER_TERRAFORM.rsa_public_key` and unblock Terraform Cloud.
- **Account-level operations.** Changing account parameters, managing account-level network policies, enabling or disabling Snowflake features, accessing billing — all restricted to `ACCOUNTADMIN`.
- **Security incident response.** Suspending a compromised user, revoking grants urgently, running audit queries — when acting through a PR-driven apply is too slow given the threat.

### Out of scope (must go through `USER_TERRAFORM` via a PR)

- Creating, modifying, or dropping warehouses, databases, schemas, roles, or service users.
- Adding or removing grants on any module-managed object.
- Creating tables, views, stored procedures, or streams inside managed schemas (typically owned by `ROLE_TRANSFORM` via dbt, not by Terraform).
- Changing cost limits on an existing warehouse or on the existing `THELOOK_MONTHLY_BUDGET` resource monitor.
- Any change that is expressible as a Terraform diff — by construction, it belongs in a PR.

### Logging expectation

Every `admin_bootstrap` session — regardless of scope category — is recorded either in the commit message of the PR it unblocked, or in a dated runbook entry if it is incident-driven. The recorded fields are: date, reason, operations performed, and whether a follow-up PR is needed to converge the Terraform state.

## Consequences

### Positive

- Break-glass availability is preserved without the overhead of managing a second dedicated user.
- The canonical automation boundary (`USER_TERRAFORM` ≠ `ACCOUNTADMIN`) is fully enforced; the RBAC benefit of the rotation is banked.
- No additional credentials to rotate, store, or document for a project whose threat model does not warrant them.
- The decision is reversible: moving to Option B later is straightforward once `USER_BREAK_GLASS` is introduced.

### Negative / Trade-offs

- A human, password-authenticated, `ACCOUNTADMIN`-scoped identity remains enabled in the account. In an enterprise or production context, this would fail most hardening reviews.
- The temptation to "just use `admin_bootstrap` to unblock a change" will exist; discipline around `USER_TERRAFORM`-first operations must be explicit.
- Slightly weaker posture than the canonical "separate break-glass + disable bootstrap" pattern documented in Snowflake's security guides.

### Risk Mitigations

- **MFA enrollment**: `admin_bootstrap` enrolled in Snowflake MFA (Duo push). This is the single most effective mitigation against credential theft.
- **Strong password**: `admin_bootstrap` password generated by a password manager (≥ 20 chars, high entropy), rotated if ever exposed.
- **No programmatic use**: `admin_bootstrap` never appears in Terraform Cloud variables, GitHub Actions secrets, or any other automation surface. The only enabled automation identity is `USER_TERRAFORM` with key-pair auth.
- **Session hygiene**: `admin_bootstrap` is used only via the Snowsight UI for explicitly-scoped break-glass tasks; every such usage is noted in the corresponding commit message or runbook entry.
- **Rotation trigger**: if `admin_bootstrap` is ever used for an operation outside the documented break-glass scope, this ADR is revisited and Option B is reconsidered.

## Pros and Cons of the Options

### Option A — Disable `admin_bootstrap`
- Good: eliminates the high-privilege interactive identity entirely; matches hardening best practice.
- Bad: removes the break-glass path; any future `ACCOUNTADMIN`-only operation (e.g. new resource monitor) requires an account-recovery or a second user that doesn't yet exist — effectively forces Option B first.

### Option B — Dedicated `USER_BREAK_GLASS` + disable `admin_bootstrap`
- Good: cleanest posture; the break-glass identity is purpose-built, clearly-named, and narrowly-used.
- Bad: one more credential to manage, rotate, and document; marginal benefit for a single-operator portfolio project; time better spent on the next capability (dlt ingestion, dbt models, BI layer).

### Option C — Retain `admin_bootstrap` with compensating controls (chosen)
- Good: preserves break-glass at zero extra credential cost; automation boundary already enforced; reversible.
- Bad: an enabled interactive `ACCOUNTADMIN` identity remains in the account; discipline required to avoid misuse.

## References

- ADR-0004: IaC for Snowflake — Terraform over SQL scripts and Snowsight UI
- [Snowflake — ACCOUNTADMIN system role overview](https://docs.snowflake.com/en/user-guide/security-access-control-considerations)
- [Snowflake — Multi-factor authentication (MFA)](https://docs.snowflake.com/en/user-guide/security-mfa)
- `infra/terraform/snowflake/terraform_rbac.tf` — `ROLE_TERRAFORM` / `USER_TERRAFORM` definitions and owner
