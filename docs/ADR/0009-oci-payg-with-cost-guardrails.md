# ADR-0009: OCI Pay-As-You-Go with €0 cost guardrails

- **Status**: Accepted
- **Date**: 2026-04-28
- **Tags**: oci, finops, cost-control, payg, security

## Context and Problem Statement

ADR-0005 committed the project to OCI Always Free as the always-on platform host. The initial deployment to `eu-paris-1` (the tenancy's home region, locked at account creation) failed repeatedly with `500-InternalError, Out of host capacity` on the `VM.Standard.A1.Flex` shape, a known scarcity issue on saturated regions. Reducing the shape from 4 OCPU / 24 GB to 2 OCPU / 12 GB did not improve availability, indicating systemic A1 contention in Paris rather than a shape-specific limit.

The natural mitigation (deploy in a region with better A1 availability, `eu-frankfurt-1`) was blocked by an OCI Free Trial limit: **the tenancy is capped at one subscribed region** (the home region), and the "Subscribe" button on Frankfurt was disabled with `You have exceeded the maximum number of regions allowed for your tenancy`. This limit, tightened by Oracle in 2024 to deter "region shopping" for A1 capacity, is not negotiable on Free Trial.

The only path to unblock the platform was to upgrade the tenancy from Free Trial to **Pay-As-You-Go (PayG)**. Always Free resources remain free for life on PayG; the upgrade unlocks region subscriptions and other operational features. The trade-off: a credit card is added to the tenancy, exposing the project to potential billing if any non-Always-Free resource is ever provisioned (accidentally or maliciously).

The decision is therefore not whether to upgrade (without it, the project cannot proceed), but **how to upgrade safely while preserving the €0 TCO commitment that justifies the entire architecture**.

## Decision Drivers

- **€0 TCO is non-negotiable**: this is the central marketing claim of the architecture (ADR-0005). Any decision that introduces real billing risk undermines the whole project.
- **Defense in depth**: a single guardrail (e.g. budget alerts only) is fragile. Multiple independent layers must each prevent a different failure mode.
- **Hard cap vs. soft cap**: OCI Budgets are *alerting*, not *blocking*; they detect overspend after the fact. A real €0 cap requires Compartment Quotas, which *block* provisioning of paid resources at creation time.
- **Reversibility**: the option chosen must allow reverting to Free Trial-equivalent constraints if Always Free terms tighten further or if the platform is wound down.
- **Operational simplicity**: this is a single-operator project. A cap strategy that requires daily attention or third-party tooling is not sustainable.

## Considered Options

- **Option A**: Stay on Free Trial, work around the A1 capacity issue. Retry Paris at off-peak hours; reduce to the smallest A1 shape (1 OCPU / 6 GB); fall back to non-A1 Always Free shapes (`E2.1.Micro` is too small for Dagster).
- **Option B**: Upgrade to PayG, no additional guardrails. Rely solely on careful Terraform code review and OCI's default Always Free service-side limits.
- **Option C**: Upgrade to PayG with a four-layer defense (Compartment Quotas as hard block, Budget canary at 0.01 EUR as early detection, MFA on the tenancy admin user as anti-compromise, IaC-only resource creation as audit trail).

## Decision

Chosen option: **Option C** (PayG with four-layer defense), because Option A is operationally untenable (multi-day blocker on capacity that may never resolve in Paris), Option B exposes the project to unbounded billing in case of credential compromise or accidental misprovisioning, and Option C delivers the unblock without sacrificing the €0 TCO commitment that the whole architecture is built on.

Concretely, the upgrade was performed only **after** the four defense layers were coded and applied while the tenancy was still on Free Trial (defense first, exposure second).

## The Four Defense Layers

### Layer 1: Compartment Quotas (hard cap, blocks provisioning)

`infra/terraform/oci/quotas.tf` declares a tenancy-level `oci_limits_quota` that blocks paid services. The OCI Quota Policy DSL is finicky, `AND` is unsupported in `WHERE` clauses, and many "obvious" quota names do not exist, so the initial cut is conservative:

- `Zero database quotas in tenancy`: blocks all Autonomous Database creation. Safe because the project uses Snowflake (ADR-0006), not ADW.
- `Zero load-balancer quotas in tenancy`: blocks Flexible Load Balancers. Safe because public access is via OCI Bastion (port-forwarding sessions), not via a public LB.

Each statement is one condition per `WHERE` (DSL constraint discovered the hard way). Per-shape quota names for compute and block-storage are deferred to a follow-up extension once verified against the live tenancy via `oci limits quota list-quota`.

This file uses an aliased provider (`oci.home`) pinned to `var.home_region` (`eu-paris-1`) because **OCI rejects quota and budget operations from any region other than the home region** with `403-NotAllowed`. Discovered the hard way during the Paris-to-Frankfurt migration.

### Layer 2: Budget canary (soft cap, detects spend early)

`infra/terraform/oci/budget.tf` declares an `oci_budget_budget` capped at 1 EUR/month with five alert rules. The `oci_budget_alert_rule` at **1% threshold = 0.01 EUR** is the canary: it fires on any non-zero charge, regardless of source, including charges that bypass the quotas (data egress > 10 TB, DDoS amplification, Oracle billing artefacts). Alert recipients are configured via the `cost_alert_email` Terraform variable; the project uses two email addresses for redundancy. Like Layer 1, these resources use the `oci.home` provider alias.

The five alert thresholds were chosen for graduated response:
- Forecast 50% → forward-looking warning (trend detection).
- Actual 1% → canary.
- Actual 10% → confirmation (rules out transient billing artefacts).
- Actual 50% → escalation.
- Actual 100% → full breach, ADR revisit.

### Layer 3: MFA on the OCI admin user (anti-compromise)

The single biggest risk vector under PayG is credential theft of the tenancy admin user, leading to unbounded resource provisioning. MFA enrollment (TOTP via Duo Mobile or equivalent) was completed on the human admin user before the PayG upgrade. This mirrors the MFA decision documented for `admin_bootstrap` in ADR-0008 (Snowflake side).

The Terraform service user (`USER_TERRAFORM` on Snowflake side, the OCI API key on OCI side) does not need MFA because it authenticates via cryptographic key signature, not interactive credentials.

### Layer 4: IaC-only resource creation (audit trail)

Every chargeable OCI resource type (compute, block volume, object storage, etc.) is declared in Terraform under `infra/terraform/oci/`. The console is used only for read-only inspection and for the bastion service's interactive session creation (which is operational, not provisioning). This means every cost-bearing change must pass through a PR review and a Terraform Cloud apply. There is no path to spin up a paid resource by accident from the UI.

## Consequences

### Positive

- The Frankfurt region is now subscribable; the A1 capacity blocker is lifted.
- Always Free resources remain free for life under PayG, so the €0 TCO claim is preserved as long as the four layers hold.
- The four-layer defense produces a reusable artefact: a small but realistic FinOps governance setup, expressible in Terraform and reviewable as code.
- The decision is reversible: if Always Free terms tighten or the project is wound down, the OCI tenancy can be downgraded or terminated, and the credit card can be removed.

### Negative / Trade-offs

- A credit card is now attached to the tenancy. The "no possible billing" guarantee that Free Trial offered is replaced by a defended-in-depth posture.
- A few specific exposures bypass the current quota layer: data egress beyond 10 TB/month, DDoS amplification on a public IP, Oracle billing edge cases. These are detected by the canary, not blocked. Mitigation: the application surface is restricted to SSH-via-Bastion (no public HTTP endpoint exposed), reducing the realistic attack surface to near-zero.
- The Compartment Quotas DSL is finicky and the initial coverage is narrower than originally drafted (Database, Load Balancer only). Compute, block volume, and NAT Gateway exposures are detected (canary) but not blocked. Tracked as a TODO in `quotas.tf`.
- One more credential to manage in the password vault, and a discipline cost to keep the IaC-only path clean.

### Risk Mitigations

- **Quota policy lives in `quotas.tf`**: reviewed in PRs. Any extension goes through code review.
- **Budget canary at 0.01 EUR** with two-recipient email alerting; if the quota fails to block something, the canary catches it within hours.
- **MFA enforced** on the admin user; a stolen password alone cannot provision paid resources.
- **The project does not expose any public TCP port other than 22 via the Bastion managed service**; the realistic egress attack vector is small.
- **Always Free service-side limits** still apply at the OCI service level (e.g. compute is hard-capped at 4 OCPU + 24 GB on A1 across the tenancy regardless of our quotas). These are Oracle's own backstops.

## Lessons Learned (Cloud-Init Hardening)

This ADR is being written immediately after a multi-hour SSH connectivity debug session that surfaced two cloud-init pitfalls worth recording, both were silent, both produced the same symptom (`Permission denied` or `Connection closed`), and both ate significant time before being identified. The fixes are committed alongside this ADR.

### Pitfall 1: `users:` block without `- default`

When cloud-init's `users:` directive is present, it **replaces** the distribution's default user list rather than appending to it. On the OCI Ubuntu image, the default list contains the `ubuntu` user that is the target of `metadata.ssh_authorized_keys` (set in `compute.tf`). Without an explicit `- default` as the first item in `users:`, the `ubuntu` user is silently never created, the SSH key has no recipient, and Bastion-tunneled SSH fails with `Permission denied (publickey)` even though the tunnel and key are correct.

**Fix in code:** `cloud-init.yaml` now has `- default` as the first entry in `users:`, with an explicit comment documenting why it is non-optional.

### Pitfall 2: Custom `iptables` rules.v4 replacing OCI Ubuntu defaults

The original `cloud-init.yaml` included a `write_files` entry for `/etc/iptables/rules.v4` followed by `iptables-restore` in `runcmd`, intended as a defense-in-depth layer over the OCI Security List. The ruleset opened tcp/80 and tcp/443 but **silently dropped tcp/22** because the default policy was `INPUT DROP` and port 22 had no explicit `ACCEPT` line.

The OCI Ubuntu image already ships with a sensible iptables ruleset (`INPUT policy ACCEPT`, explicit `ACCEPT` for tcp/22, generic `REJECT` at the end) which the cloud-init `iptables-restore` was overwriting. Combined with the order-of-operations subtleties of `iptables-persistent` install on ARM under cloud-init, this produced the confusing symptom of *the bastion tunnel establishing TCP and then the VM closing the connection without ever sending the SSH banner*.

**Fix in code:** the entire custom iptables block has been removed from `cloud-init.yaml`. The image's default ruleset is sufficient at the OS layer; the OCI Security List handles the network layer; fail2ban handles the application layer. A custom iptables ruleset can be reintroduced later in a dedicated commit + ADR if a specific need arises (e.g. internal-only port restrictions for Cube Cloud egress).

### Generalisable takeaway

Cloud-init silently overwriting OS defaults is a recurring class of bug. The mitigation is to **explicitly declare what is being preserved** (`- default` for users, the OS iptables rules by not touching them) and to **bisect by removing all cloud-init customisations** when SSH is unreachable on a freshly-booted VM. The bisection approach took us from "SSH never works" to "SSH works on minimal cloud-init" to "the two specific blocks that were breaking SSH" in under 30 minutes once applied, far faster than continuing to iterate on the full ruleset.

## References

- ADR-0005: Always-on platform, OCI Free Tier
- ADR-0006: Single analytic engine, Snowflake
- ADR-0008: admin_bootstrap retained as break-glass with mitigations
- `infra/terraform/oci/quotas.tf`, Compartment Quotas (Layer 1)
- `infra/terraform/oci/budget.tf`, Budget + alert rules (Layer 2)
- `infra/terraform/oci/main.tf`, `oci.home` provider alias for tenancy-level operations
- `infra/terraform/oci/cloud-init.yaml`, fixed cloud-init (with `- default` and without custom iptables)
- [OCI Compartment Quotas, Quota Policy Language](https://docs.oracle.com/en-us/iaas/Content/General/Concepts/resourcequotas.htm)
- [OCI Budgets overview](https://docs.oracle.com/en-us/iaas/Content/Billing/Concepts/budgetsoverview.htm)
- [Cloud-init `users` and `groups` module, `default` keyword](https://cloudinit.readthedocs.io/en/latest/reference/modules.html#users-and-groups)
