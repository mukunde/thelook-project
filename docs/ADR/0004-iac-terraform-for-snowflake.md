# ADR-0004: Terraform over SQL scripts and Snowsight UI for Snowflake IaC

- **Status**: Accepted
- **Date**: 2026-04-20
- **Tags**: iac, terraform, snowflake, platform-engineering

## Context and Problem Statement

The project operates Snowflake under a strict "demo-on-demand warehouse" policy: the warehouse is provisioned via `terraform apply` at the start of an active period (demo, development sprint) and destroyed via `terraform destroy` at the end. This implies that the full Snowflake footprint (databases, schemas, warehouses, roles, grants, service users) must be reproducible from code in minutes, not manual clicks.

Beyond reproducibility, there is value in treating the data warehouse as declarable infrastructure, like a VPC, an S3 bucket, or a Kubernetes cluster. Declaration forces the platform to be describable, diffable, and reviewable as code rather than as tribal knowledge.

## Decision Drivers

- **Reproducibility**: the entire Snowflake footprint must rebuild identically from any git commit.
- **Auditability of RBAC**: five roles (ingestion, transform, three analyst personas) and their grants are security-sensitive and must be reviewable in PRs.
- **Demo-on-demand workflow**: rebuild in ≤ 5 minutes, teardown in ≤ 3 minutes, zero manual intervention.
- **Consistency with OCI provisioning**: the OCI infrastructure is also managed via Terraform, using the same tool reduces cognitive load and unifies the workflow.
- **Remote state with locking**: needed to prevent concurrent `apply` conflicts and to support reliable CI/CD.

## Considered Options

- **Snowsight UI** (click-ops), fast initial setup, zero reproducibility, no audit trail.
- **Versioned SQL scripts**: imperative, no state management, manual drift detection, error-prone on destroy/recreate cycles.
- **Terraform with the `snowflakedb/snowflake` provider**: declarative, state-aware, idempotent, same tool as OCI. Officially maintained by Snowflake since v2.0.0 (migrated from the former community `Snowflake-Labs` namespace).
- **Pulumi with Snowflake provider**: same model as Terraform but in Python/TypeScript; smaller community and less Snowflake-provider maturity.
- **Custom Python with `snowflake-connector-python`**: maximum flexibility, maximum maintenance burden, no state management primitive.

## Decision

I chose **Terraform with the `snowflakedb/snowflake` provider** (officially maintained by Snowflake since the v2.0.0 GA release, migrated from the former `Snowflake-Labs` community namespace), with remote state hosted on Terraform Cloud Free Tier. The declarative model, the alignment with OCI provisioning, and the remote state with locking make it the only option that satisfies the demo-on-demand workflow and the auditability requirement together.

## Consequences

### Positive

- A `terraform plan` output is reviewable in every PR that touches infrastructure, giving the same review discipline to data platform changes as to backend code.
- The full Snowflake footprint rebuilds in 3–5 minutes; teardown is a single command.
- RBAC and grants live in a dedicated `grants.tf` file, reviewed as code, with full drift detection.
- The same Terraform toolchain drives both Snowflake and the OCI VM, one CLI, one state backend, one mental model.
- Remote state on Terraform Cloud provides free state locking, versioning, and five-user collaboration.

### Negative / Trade-offs

- Learning curve for engineers coming from a pure-SQL background: Terraform language, state concepts, provider peculiarities.
- The provider underwent significant reworks in v1.0.0 and v2.0.0; stable resources are officially supported by Snowflake since v2.0.0, but some resources remain flagged as "preview" in the documentation and can introduce breaking changes even without a major version bump, I pin to stable resources only.
- Requires a Terraform Cloud account (free) in addition to the Snowflake and OCI accounts, one more credential to manage.
- Secrets (Snowflake account URL, service user passwords or key pairs) must be managed as Terraform Cloud workspace variables, not in the repo.

### Risk Mitigations

- Well-established patterns exist in the provider documentation and community repositories; I follow them rather than inventing new structures.
- Service account credentials are provisioned once, rotated manually if needed, and stored in Terraform Cloud workspace variables (encrypted at rest).
- Grant diffs that create noise in plans are pinned with explicit lifecycle rules when they appear.

## Pros and Cons of the Options

### Terraform + snowflakedb/snowflake provider
- Good: declarative, idempotent, state-aware, same tool as OCI, free remote state, officially supported by Snowflake (stable resources, v2.0.0+).
- Bad: learning curve, some resources still in "preview" with breaking-change risk, one more account to manage.

### Versioned SQL scripts
- Good: familiar to SQL-focused engineers, no new language.
- Bad: imperative, no drift detection, destroy/recreate cycles become risky, no state.

### Snowsight UI
- Good: fast for a first setup.
- Bad: not reproducible, not auditable, no audit trail on RBAC changes.

## References

- [snowflakedb/snowflake Terraform provider (Terraform Registry)](https://registry.terraform.io/providers/snowflakedb/snowflake/latest)
- [Snowflake Terraform provider, official documentation](https://docs.snowflake.com/en/user-guide/terraform)
- [Terraform Cloud Free Tier](https://developer.hashicorp.com/terraform/cloud-docs/overview)
