# ADR-0005: Always-on platform compute — OCI Free Tier

- **Status**: Accepted
- **Date**: 2026-04-20
- **Tags**: hosting, oci, tco, always-on, platform

## Context and Problem Statement

The project requires several services to be publicly accessible 24/7 — not only during active demos:

- Dagster UI (orchestration, lineage, run history)
- Metabase (live and cached BI dashboards)
- A Postgres instance for Dagster metadata
- A Postgres instance for Metabase application data
- A reverse proxy with TLS (Caddy)

These services must stay online between active periods, while Snowflake is destroyed. The compute platform must therefore be **always-on and free permanently** — not free for a limited introductory period. It must also be provisionable via Terraform to stay consistent with the Snowflake IaC strategy.

## Decision Drivers

- **Permanent free tier** (not a 12-month trial).
- **Enough RAM and CPU** to run Dagster + Metabase + two Postgres instances + Caddy simultaneously with headroom.
- **Public static IP** for stable DNS and Let's Encrypt certificates.
- **Terraform provider** to fit the IaC pattern.
- **TLS support** with automatic certificate renewal.
- **Data residency in the EU** to keep latency acceptable from a French workstation.

## Considered Options

- **Laptop / home server** — no 24/7 availability guarantee, residential IP issues, no stable public URL.
- **AWS EC2 `t2.micro` free tier** — 1 vCPU / 1 GB RAM, 750h/month for 12 months only. Insufficient RAM and expires.
- **GCP `e2-micro` Always Free** — 1 vCPU / 1 GB RAM, permanent but very limited RAM; geographical constraints for "Always Free" eligibility.
- **Fly.io free allowance** — shared CPU, ~256 MB RAM per machine, credit-based — insufficient for the stack and risk of runaway credit consumption.
- **Render.com free web services** — sleep after inactivity (cold start on every request), disqualifying for a "always-on" requirement.
- **Railway** — no meaningful free tier anymore (trial credits only).
- **Hetzner Cloud** — not free, but the cheapest credible paid fallback (~€4–5/month).
- **Dagster+ Cloud free** — trial 30 days only, paid beyond.
- **OCI Always Free — ARM Ampere A1 Flex** — up to 4 OCPU / 24 GB RAM / 200 GB block storage, permanent free tier.

## Decision

I chose **OCI Always Free with an ARM Ampere A1 Flex VM (4 OCPU / 24 GB RAM / 200 GB)**. No other free tier comes close in specs, and OCI's `oracle/oci` Terraform provider fits the IaC pattern without compromise.

## Consequences

### Positive

- The stack (Caddy + Dagster webserver + Dagster daemon + Postgres + Metabase + Postgres) fits comfortably within 24 GB of RAM with significant headroom.
- Permanent free tier — no 12-month countdown, no credit consumption risk under normal use.
- The `oracle/oci` Terraform provider is official and well-maintained; I manage OCI infrastructure exactly like Snowflake.
- The split "always-on platform on OCI, demo-on-demand warehouse on Snowflake" becomes viable at strictly €0: the non-trivial part of the stack runs permanently, the expensive analytics compute is ephemeral.
- OCI Bastion (included in Always Free, 5 sessions) eliminates the need to expose SSH on the public internet.
- Object Storage (10 GB Always Free) covers weekly Docker volume backups.

### Negative / Trade-offs

- **ARM A1 capacity is sometimes saturated** in certain European regions, leading to "Out of Capacity" errors on `terraform apply`. This is the single most frequently cited issue with OCI Always Free.
- OCI is less familiar than AWS or GCP to most engineers — there is a small tax on onboarding or hand-offs.
- As a self-hosted Linux VM, I carry responsibility for OS patching, Docker security, fail2ban, and basic hardening.
- Idle reclaim policy: Oracle reserves the right to reclaim Always Free instances that remain below 20 % CPU at the 95th percentile for extended periods.
- Free tier terms can change with notice — non-zero long-term risk.

### Risk Mitigations

- **Region strategy**: the first `terraform apply` targets Frankfurt or Amsterdam; documented fallbacks are Zurich, Paris, London, and Marseille. A short retry loop is acceptable during initial bootstrap.
- **Idle reclaim**: Dagster daily schedules plus periodic Metabase queries easily exceed the 20 % CPU threshold at the 95th percentile, putting the VM well outside the reclaim criteria.
- **OS hardening baseline**: `unattended-upgrades`, `fail2ban`, SSH via OCI Bastion only, ed25519 keys, no password auth, Caddy handles TLS automatically.
- **Backup strategy**: weekly `rclone` dump of `/var/lib/docker/volumes` to OCI Object Storage.
- **Free tier policy change**: documented rollback path to Hetzner Cloud (≈ €5/month) — adds a line to the TCO but does not break the architecture.

## Pros and Cons of the Options

### OCI Always Free (ARM A1 Flex)
- Good: 4 OCPU / 24 GB / 200 GB permanent, Terraform provider, EU regions, Bastion and Object Storage included.
- Bad: capacity saturation in some regions, less mainstream than AWS/GCP, OS maintenance burden, policy-change risk.

### AWS `t2.micro`
- Good: familiar AWS path.
- Bad: 12-month only, 1 GB RAM insufficient for the stack.

### Fly.io
- Good: fast deploy, good DX.
- Bad: RAM caps and credit model incompatible with a non-trivial always-on stack.

### Render / Railway
- Good: simple deploy.
- Bad: free tiers sleep or have disappeared — fail the always-on requirement.

## References

- [OCI Always Free resources](https://www.oracle.com/cloud/free/)
- [oracle/oci Terraform provider](https://registry.terraform.io/providers/oracle/oci/latest)
