# ADR-0000: Snowflake on AWS as the data warehouse

- **Status**: Accepted
- **Date**: 2026-04-18
- **Tags**: foundation, data-warehouse, snowflake, aws

## Context and Problem Statement

This ADR is the foundation of the entire `thelook-mds` project: the choice of the analytical engine and its hosting cloud. Every subsequent ADR extends this initial decision and would be reconsidered if it changed: ingestion tooling (ADR-0001), orchestration (ADR-0002), BI surface (ADR-0003), Terraform for Snowflake (ADR-0004), the OCI always-on platform (ADR-0005), the single-engine commitment (ADR-0006), the semantic layer (ADR-0007), and the operational ADRs that followed (ADR-0008, ADR-0009).

This is a personal data engineering project, designed to be representative of a real French data team's stack circa 2026 while operating under a €0 total cost of ownership constraint. That dual goal (alignment with French market practice *and* free to operate) drives every selection criterion below.

The arbitration is therefore not "which warehouse is technically best in absolute terms" (a question without a useful answer), but "which warehouse + cloud combination best satisfies the four constraints below, given the French data engineering market in 2026 and the €0 TCO commitment".

## Decision Drivers

- **French market alignment.** The chosen warehouse must reflect the tooling actually used by analytics engineering and data engineering teams in France in 2026, as visible in job postings, in community discussions, and in cross-industry technology surveys. Niche or experimental tooling, however technically interesting, is excluded.
- **Modern analytical architecture.** The warehouse must demonstrate the architectural patterns that define the "modern data stack": separation of storage and compute, automatic scaling, native semi-structured data handling (JSON/Parquet), time travel, zero-copy cloning, and first-class SQL. Older paradigms (pure shared-nothing MPP, on-prem-first products) are excluded.
- **Cloud-agnosticism.** The warehouse should run on multiple major clouds (AWS, GCP, Azure) so that the architectural skills transfer across employers. Pure cloud-native warehouses tied to a single provider create lock-in that limits the project's reach.
- **Realistic source/destination separation.** A pipeline where ingestion is trivial (warehouse and source live in the same provider account) does not exercise the integration and reliability skills a production data engineer is hired for. The chosen warehouse should be on a *different* cloud than the source dataset, forcing a real ingestion design (authentication, network, incremental loads, retries) that mirrors enterprise reality. This is treated as an explicit learning objective of the project, not merely a side-effect.
- **€0 TCO compatibility.** The warehouse must be operable at zero recurring cost over the duration of an active project iteration (≥ 1 month). A free tier or a sufficiently generous trial is mandatory. Pay-per-query and per-second pricing models are acceptable as long as the consumption envelope of the project (a few GB ingested, a few hundred dbt runs/month) stays inside the free allowance.

## Considered Options

- **Snowflake on AWS.** Cloud-agnostic warehouse running on AWS (also available on GCP and Azure). Separation of storage and compute, per-second billing, 30-day trial with $400 of credits.
- **BigQuery on GCP.** GCP-native warehouse. On-demand pricing (1 TB free queries/month, 10 GB free storage/month) with no time-bound trial; perpetual free tier.
- **Databricks Lakehouse on AWS.** Lakehouse architecture (Delta Lake on object storage), unified for analytics + ML. 14-day trial.
- **Amazon Redshift on AWS.** AWS-native warehouse, traditional MPP architecture (RA3 nodes separate storage from compute since 2019). 2-month trial with the `dc2.large` shape. Older codebase than Snowflake/BigQuery, less aligned with modern dbt-first patterns.

## Decision

Chosen option: **Snowflake on AWS**, because it is the only option that satisfies all five decision drivers simultaneously, with the source/destination separation criterion being decisive against BigQuery (which would have been the easier choice on cost alone but defeats the realism objective).

The AWS region was selected over Snowflake-on-GCP and Snowflake-on-Azure because, in observed French job postings and in the Malt Tech Trends 2025 and 2026 reports (see References), AWS is the most common cloud underneath Snowflake deployments, and the broader AWS ecosystem (IAM, S3, Lambda) is the second most asked-for skillset alongside Snowflake itself. The specific AWS region (`eu-west-1` Ireland or `eu-west-3` Paris) is left to the Terraform variable; the trial account defaults to whichever region the user signed up under.

## Consequences

### Positive

- **Market reach.** Snowflake and AWS are among the most-mentioned data and cloud technologies in French analytics engineering and data engineering job postings in 2026. The combination of the two strengthens the project's relevance further: most large enterprises in France with a Snowflake deployment also have an AWS footprint.
- **Realistic ingestion problem.** Because the source dataset (TheLook eCommerce) lives on GCP BigQuery and the warehouse lives on AWS-hosted Snowflake, ingestion must traverse cloud boundaries, exercising authentication (service accounts on GCP, key-pair on Snowflake), network (egress from BigQuery), and incremental load patterns (dlt with state management, see ADR-0001). This is the kind of integration work a real data engineer ships.
- **Hands-on coverage of Snowflake-native features.** Time travel, zero-copy cloning, RBAC modelled with custom roles (ADR-0008), resource monitors for cost control, multi-warehouse separation (ingestion/transform/consumer), all are documented and exercised in the project's `infra/terraform/snowflake/` module rather than glossed over.
- **Cloud-agnostic architecture transfers.** The dbt models, the semantic layer (ADR-0007), and the orchestration patterns (ADR-0002) would port to Snowflake on Azure or GCP with minimal change, which makes the project's content useful in contexts beyond a strictly AWS-centric one.
- **Same Terraform provider story as the OCI module** (ADR-0005). Both Snowflake and OCI are managed declaratively (ADR-0004), giving a coherent IaC narrative across the whole project.

### Negative / Trade-offs

- **30-day trial expiry.** Unlike BigQuery's perpetual sandbox, the Snowflake trial is time-boxed. After 30 days the account must either be upgraded to a paid plan (real billing exposure, requires cost-control discipline) or rotated to a fresh trial (operationally fragile, may not be permitted by Snowflake terms).
- **Cross-cloud egress cost.** Reading from BigQuery and writing to Snowflake-on-AWS incurs GCP egress charges (≈ $0.12/GB in 2026). At the project's data volumes (a few GB total) this is negligible (cents per full reload), and dlt's incremental loading reduces it further, but it exists.
- **Higher cold-start setup than BigQuery.** BigQuery requires a single GCP project and the dataset is queryable in a minute. Snowflake requires an account (URL, region, edition), a provisioned warehouse, RBAC setup, and key-pair authentication, which is ≈ 1-2 days of Terraform work (now captured in `infra/terraform/snowflake/`). For this project this is content, not friction; for a production team in a hurry, BigQuery would be faster.
- **Snowflake-on-AWS lock-in is partial.** While Snowflake itself is cloud-portable, account-level features (like data residency or edition tier) tie the deployment to a specific region/cloud. Migrating Snowflake-on-AWS to Snowflake-on-GCP is non-trivial despite the same product.

### Risk Mitigations

- **Trial expiry is anticipated.** When the 30-day trial expires, the account will be upgraded to a paid Snowflake plan with cost-control already pre-instrumented: the resource monitor `THELOOK_MONTHLY_BUDGET` declared in `infra/terraform/snowflake/` is capped at 10 credits/month and acts as the hard ceiling. The defense-in-depth philosophy applied to OCI in ADR-0009 (hard cap + soft alerts) carries over conceptually, even though Snowflake's commercial structure differs from OCI's Pay-As-You-Go tier.
- **Egress is monitored.** Ingestion volumes are visible in dlt's load metadata (`_dlt_loads` table) and aggregated in dbt staging models. Any abnormal volume (e.g. accidental full reload) shows up as a clear data point.
- **Skills are portable.** dbt models and the semantic layer use vendor-neutral SQL where possible. A future migration to Snowflake-on-Azure, or even to BigQuery, would primarily require rewriting `infra/terraform/snowflake/` and a small set of SQL functions, not re-architecting the project.

## Pros and Cons of the Options

### Snowflake on AWS (chosen)
- Good: cloud-agnostic warehouse, top-tier French market presence, modern architecture (separation of storage/compute, time travel, zero-copy cloning), strong ecosystem with dbt/Dagster/Cube, AWS as the dominant adjacent cloud.
- Bad: 30-day trial then paid upgrade required, cross-cloud egress from BigQuery source, longer initial setup than BigQuery.

### BigQuery on GCP
- Good: perpetual free tier (1 TB queries + 10 GB storage / month) easily fits the project's workload, zero-setup ingestion if the source is also on GCP, popular in tech startups in France.
- Bad: GCP-native (locks the project's portability narrative), source-on-same-cloud kills the realistic ingestion learning objective, somewhat less prevalent than Snowflake in larger French enterprises in 2026 according to the Malt Tech Trends 2025 and 2026 reports.

### Databricks Lakehouse on AWS
- Good: lakehouse pattern (Delta Lake on S3) is rising, strong in ML/AI-adjacent roles.
- Bad: 14-day trial (shorter than Snowflake), the unified ML/SQL model is less aligned with a pure analytics engineering project, more setup complexity for the same SQL-first outcome.

### Amazon Redshift on AWS
- Good: native AWS, RA3 nodes do separate storage and compute since 2019, 2-month trial.
- Bad: less dbt-aligned tooling than Snowflake (cluster-style provisioning vs Snowflake's per-second warehouse), older codebase that drags some legacy MPP idioms, declining mindshare in French analytics engineering job postings vs Snowflake.

## References

- [Malt Tech Trends 2026](https://www.malt.fr/resources/trends/malt-tech-trends), primary source for French freelance market technology trends in 2026, including data warehouses, cloud providers, and the relative weight of Snowflake/BigQuery/Databricks among French tech missions and demanded skills.
- [Malt Tech Trends 2025, Décryptage des évolutions technologiques et des compétences clés](https://www.malt.fr/resources/article/malt-tech-trends-2025--decryptage-des-evolutions-technologiques-et-des-competences-cles), prior-year edition of the same report, useful for year-over-year trajectory of the same indicators.
- [Datagen YouTube channel](https://www.youtube.com/@data-gen), French data community channel, recurring discussions of the Snowflake / BigQuery / Databricks landscape and adoption patterns in French companies.
- LinkedIn and Indeed job postings filtered on "Analytics Engineer France" and "Data Engineer France" (April 2026): qualitative observation that Snowflake and BigQuery dominate the warehouse mentions, with Snowflake the more frequent of the two in larger enterprises and BigQuery more common in tech startups; Databricks present as a secondary mention especially in roles blending data engineering and ML; Redshift increasingly residual.
- [dbt Labs, State of Analytics Engineering Report](https://www.getdbt.com/state-of-analytics-engineering-report), annual industry survey, useful baseline for cross-referencing French market specifics against global trends.
- [Snowflake, official Pricing & Editions documentation](https://www.snowflake.com/en/data-cloud/pricing-options/), basis for trial credits and per-second billing assumptions.
- [BigQuery, Sandbox limits and pricing](https://cloud.google.com/bigquery/pricing), basis for the perpetual free tier comparison.
- [Snowflake Resource Monitors documentation](https://docs.snowflake.com/en/user-guide/resource-monitors), basis for the trial-to-paid cost control narrative referenced in Risk Mitigations.
- ADR-0001 (ingestion: dlt over Airbyte), ADR-0004 (Terraform for Snowflake), ADR-0005 (always-on platform on OCI), ADR-0006 (single analytic engine, Snowflake), ADR-0009 (OCI PayG cost guardrails, pattern that informs the future Snowflake trial-to-paid transition).
