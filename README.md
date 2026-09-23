# retail-customer-intelligence

[![CI/CD](https://github.com/modern-data-engineering-lab/retail-customer-intelligence/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/modern-data-engineering-lab/retail-customer-intelligence/actions/workflows/ci-cd.yml)

A dbt-on-Databricks analytics-engineering repo: RFM segmentation, churn-risk features, and
customer LTV on the real [Olist Brazilian E-Commerce](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
dataset (about 99k orders, 96k customers). The Databricks workspace, Unity Catalog catalogs,
and CI/CD conventions here are shared with
[`databricks-bundle-template`](https://github.com/modern-data-engineering-lab/databricks-bundle-template),
which provisioned that shared platform layer; this repo builds its own schema, service
principals, and dbt project on top of it.

## Problem

Most dbt-on-Databricks example repos stop at "staging to one mart." That's not where the real
skill gap is. This repo goes deeper into dbt-databricks specifically: Unity Catalog three-level
namespacing, a real incremental model using Delta's native `merge` strategy, an SCD2 snapshot,
seeds versus sources, custom test macros, and a native `dbt_task` running inside a Lakeflow Job
deployed via a Databricks Asset Bundle. The actual mechanics of running dbt *on* Databricks, not
just *against* it from a laptop.

## Architecture

```
9 Kaggle CSVs                Unity Catalog volume            dbt_build job (Lakeflow)
data/raw/          ──cp──▶   /Volumes/<catalog>/            ┌─────────────────────────┐
                              retail_customer_intelligence/  │ load_bronze (notebook)   │
                              raw/                            │  reads volume, writes    │
                                                               │  8 bronze Delta tables   │
                                                               └───────────┬─────────────┘
                                                                           ▼
                                                               ┌─────────────────────────┐
                                                               │ dbt_build (dbt_task)     │
                                                               │  deps → seed → build     │
                                                               │  → docs generate         │
                                                               └───────────┬─────────────┘
                                                                           ▼
                          seeds/                     staging (8 views)  → intermediate (4)
                          product_category_          → marts/customer/ (dim_customers,
                          name_translation.csv          fct_customer_rfm, _churn_risk, _ltv)
                                                       → snapshots/customer_location_snapshot

        push to               GitHub Actions
        stg / main    ──▶    ┌──────────┐  deploy -t staging   ┌──────────────────┐
                              │  ruff    │─────────────────────▶│ staging_catalog.  │
                              └────┬─────┘                       │ retail_customer_  │
                                   ▼                              │ intelligence      │
                              ┌──────────┐  deploy -t prod       └──────────────────┘
                              │dbt build │─────────────────────▶┌──────────────────┐
                              │(vs. stg) │                       │ prod_catalog.     │
                              └──────────┘                       │ retail_customer_  │
                                                                  │ intelligence      │
                                                                  └──────────────────┘
```

Pushing to `stg` deploys to the `staging` GitHub environment, pushing to `main` deploys to
`production`, and both are gated behind `ruff` and a real `dbt build` against the staging
catalog. Each environment is branch-locked in GitHub itself, so a push from the wrong branch
can't deploy to the wrong place even if the workflow file had a bug in its `if:` condition.

### Design decisions (the *why* behind the *what*)

**Why `customer_unique_id`, never `customer_id`.** Olist's `customer_id` is generated fresh per
*order*, not per person. The same human can have several `customer_id`s across orders,
sometimes with different recorded addresses. `customer_unique_id` is the actual identity.
Getting this backwards is the single most common mistake in Olist RFM tutorials online; every
staging model, join, and mart here is keyed on `customer_unique_id` deliberately.

**Why Terraform reads the shared catalogs instead of owning them.** `staging_catalog` and
`prod_catalog` already exist, provisioned by `databricks-bundle-template`'s Terraform.
`databricks_grants` is authoritative for the *entire* grant list of whatever it targets, so a
second Terraform state declaring grants on the same catalog would fight the other one's state
over ownership: each `apply` would silently strip the other's grants. This repo's Terraform
only reads the catalogs (`data "databricks_catalog"`) and grants at the **schema** level, where
it has sole ownership; granting `USE CATALOG` on the shared catalog is a one-time manual step
via the Grants API instead (see `terraform/README.md`).

**Why `fct_customer_rfm` has fewer rows than `dim_customers`.** 1,106 of 96,096 customers
(about 1.2%) have orders that were *all* canceled or unavailable: no real purchase behavior to
assign a Recency/Frequency/Monetary score to. RFM intentionally excludes them rather than
faking a score; `fct_customer_churn_risk` and `fct_customer_ltv` still cover every customer.
`tests/assert_mart_customer_counts_match.sql` encodes this as a strict-subset check, not an
exact-match one. Its original one-directional version passed silently despite the gap; see
Troubleshooting.

**Why the payment-reconciliation test is a warning, not a hard failure.** 303 of 99,441 orders
(about 0.30%) don't reconcile between item totals and payment totals within a cent, checked
directly against the real warehouse, not assumed. A sample of the mismatches points to genuine
freight/discount timing in Olist's own source data, not a join bug here. Documented as an
accepted tolerance (`config(severity="warn")`) rather than silently ignored or force-fixed.

**Why churn risk is a rule, not a model.** `churn_risk_tier` is an explicit, auditable
threshold (recency plus order frequency), not a trained classifier. The point of this repo is
dbt and Databricks depth, not building and validating a predictive model, so a transparent rule
that anyone can audit in one glance serves the actual goal better than a black-box classifier
would.

## Stack

Databricks (SQL Warehouse, Unity Catalog, Lakeflow Jobs) · dbt-core + dbt-databricks ·
Terraform · GitHub Actions

## Repository layout

```
databricks.yml                        Bundle entry point: dev/staging/prod targets.
resources/
  variables.yml                       catalog, schema, warehouse_id, raw_data_path.
  job/dbt_build.job.yml               load_bronze (notebook) -> dbt_build (dbt_task).
terraform/                            Schema/volume/service-principals inside the SHARED
                                       catalogs, see terraform/README.md.
dbt/
  dbt_project.yml
  packages.yml                        dbt_labs/dbt_utils.
  profiles/profiles.yml.example       dev/ci/staging/prod targets for local CLI use.
  seeds/product_category_name_translation.csv
  models/
    staging/          8 source-backed views + 1 seed-backed view, schema tests.
    intermediate/      4 models, incl. int_order_items_enriched (incremental, Delta merge).
    marts/customer/    dim_customers, fct_customer_rfm, fct_customer_churn_risk,
                        fct_customer_ltv.
  snapshots/customer_location_snapshot.sql   SCD2 on customer location.
  macros/rfm_score.sql                ntile(5) scoring, direction-aware (recency inverted).
  tests/                              3 custom business-rule tests.
src/ingestion/load_bronze.py          Notebook task: 8 raw CSVs -> Delta bronze tables.
data/raw/                             .gitignored, local landing spot for the Kaggle CSVs.
.github/workflows/ci-cd.yml
```

## Getting Started

Built and verified against a Databricks Free Edition workspace, using
`databricks-bundle-template`'s catalogs and this repo's own schema underneath them.

1. **Download the dataset.** Kaggle → [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
   → unzip the 9 CSVs into `data/raw/` (gitignored).
2. **Copy the seed.** `cp data/raw/product_category_name_translation.csv dbt/seeds/`, the one
   table small and static enough to be a real dbt seed instead of a bronze table.
3. **Terraform.**
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars   # fill in warehouse_id (see comments)
   export GITHUB_TOKEN=<your-token>
   terraform init && terraform apply
   ```
   Then run the two commands from `terraform output manual_use_catalog_grant_commands`, the
   one thing Terraform can't do here (see Design decisions above).
4. **Upload the CSVs** to both volumes:
   ```bash
   terraform output staging_raw_volume_path
   terraform output prod_raw_volume_path
   for f in data/raw/olist_*.csv; do
     databricks fs cp "$f" "dbfs:${staging_volume_path}/$(basename "$f")" --overwrite
   done
   # repeat for the prod path
   ```
5. **Wire `databricks.yml`'s `prod` target** with `terraform output prod_service_principal_application_id`.
   This needs the Application ID (a UUID), not the display name: `run_as` on a Databricks
   Asset Bundle only accepts a service principal by its Application ID, and passing the display
   name instead fails deploy with a permission error that doesn't obviously point at the real
   cause.
6. **GitHub environments and secrets.** Terraform already created the `staging`/`production`
   environments (branch-locked to `stg`/`main`). Set, per environment: `DATABRICKS_HOST`,
   `DATABRICKS_CLIENT_ID`, `DATABRICKS_CLIENT_SECRET` (from
   `terraform output *_service_principal_client_secret`), `DBT_WAREHOUSE_HTTP_PATH` (from
   `terraform output warehouse_http_path`), plus the same four **at the repository level** (no
   environment) for CI's `dbt-build` job, which always tests against staging regardless of
   branch (see Troubleshooting for why it can't use the `staging` *environment* directly).
7. **First deploy.**
   ```bash
   databricks bundle validate -t staging
   databricks bundle deploy -t staging
   databricks bundle run dbt_build -t staging
   ```

## How to run locally

```bash
python -m venv .venv && .venv/Scripts/activate   # or source .venv/bin/activate
pip install -r requirements-dev.txt
cp dbt/profiles/profiles.yml.example dbt/profiles/profiles.yml   # fill in env vars, gitignored
export DBT_PROFILES_DIR=$(pwd)/dbt/profiles

cd dbt
dbt deps
dbt seed
dbt build
dbt docs generate && dbt docs serve
```

### Troubleshooting notes (real errors hit building and deploying this repo)

Every one of these was found by actually running the pipeline against the real workspace and
reading the real error or log output. Several only showed up once real data and a live
`dbt_task` were involved, not from `dbt parse` or `bundle validate` alone.

- **`dbt_task` fails with `Invalid platform channel Client-1`.** The job's serverless
  `environments[].spec.client` field is deprecated; `environment_version` is the field the
  workspace actually honors (`client: "1"` becomes `environment_version: "2"`).
- **`dbt build --target staging` fails with `profile ... does not have a target named
  'staging'`.** A native `dbt_task` auto-generates its own `profiles.yml` behind the scenes (a
  single `databricks_cluster` target, built from the task's own `catalog`/`schema`/
  `warehouse_id` fields), completely ignoring whatever targets are declared in
  `dbt/profiles/profiles.yml.example`. Don't pass `--target` in the job's dbt commands at all.
- **`olist_order_reviews_dataset.csv` loads with garbage in `review_score`.** Free-text review
  comments contain embedded newlines inside quoted fields; Spark's default (single-line) CSV
  reader misparses them and shifts every later column. Checked independently: Python's `csv`
  module parses all 99,224 rows cleanly with the same file. Fixed with
  `.option("multiLine", "true")` in `load_bronze.py`; about 16 genuinely pathological rows
  (nested quotes within a multi-paragraph comment) still don't parse even with that, and are
  quarantined via `try_cast` plus a range filter in `stg_olist__order_reviews.sql` rather than
  chased further.
- **`assert_mart_customer_counts_match` passed even though `fct_customer_rfm` had 1,106 fewer
  customers than the other marts.** The original test only checked `rfm → churn/ltv` (every RFM
  customer exists elsewhere), never the reverse. Since RFM is the smaller set by design, that
  direction is always true and the test was vacuous. Fixed to verify `churn`/`ltv` match each
  other exactly (the real invariant) and `rfm` is a strict subset of both. See Design decisions
  above for why the gap itself is legitimate, not a bug.
- **CI's `dbt-build` job fails on `main` with "Branch main is not allowed to deploy to staging
  due to environment protection rules".** Giving that job `environment: staging` seemed natural
  (it tests against the staging catalog), but the `staging` GitHub Environment is branch-locked
  to `stg` only, by Terraform's own deployment policy. A job needing staging *credentials* for
  testing isn't the same as a staging *deployment*. It now uses plain repository-level secrets
  instead of an environment-scoped set, and only `deploy-staging`/`deploy-production` keep the
  environment gate.
- **`sqlfluff lint` intermittently fails on 2 of about 20 models with a `Database Error` /
  `config auth_type: oauth is required when not using access token` error, even with valid
  credentials.** Checked consistently and in isolation against the real warehouse: a couple of
  models (`int_customer_location_current`, the incremental `int_order_items_enriched`) trigger
  a separate metadata/introspection connection during sqlfluff's `dbt` templater compilation
  that doesn't fully inherit the profile's auth config. `dbt build` itself is unaffected; this
  is specific to sqlfluff's compilation path. Dropped from the CI gate; `.sqlfluff`/`sqlfluff`
  stay in the repo for local, best-effort linting.
- **The `stg` branch didn't exist, so `deploy-staging` had never run once in this repo's
  history.** The CI workflow was correctly branch-gated from the start (`stg` deploys to
  staging, `main` deploys to production), but every commit up to this point had gone straight
  to `main`. Every prior "deploy" in this repo's history was, without anyone intending it, a
  direct production deploy with no staging rehearsal. Fixed by creating `stg` from `main` and
  starting to land work there first.
- **The first real push to the new `stg` branch fired two workflow runs for the same commit,
  and they collided.** Both ran `dbt seed --full-refresh` against the same schema at nearly the
  same moment, and one's `CREATE OR REPLACE TABLE` on the seed table stepped on the other's,
  producing a Delta `MetadataChangedException` concurrent-update error. The surviving run
  succeeded once the first one's write had already landed. Worth knowing this can happen; a
  workflow-level `concurrency:` group keyed on the branch would prevent it outright if it
  recurs.
- **`dbt build` against the real staging job failed with `PERMISSION_DENIED: User does not have
  MANAGE on Table`, for every staging model.** The job runs as a dedicated service principal,
  but the tables and views it was trying to replace had been created earlier by a personal
  account, during local development before the job-based pipeline existed. A schema-level
  `ALL_PRIVILEGES` grant doesn't retroactively grant control over objects someone else already
  owns; replacing an existing view or table needs the caller to actually own it (or have that
  ownership explicitly transferred). Regular tables were fixed by transferring ownership
  directly (`databricks tables update <full_name> --owner <service-principal-id>`). Unity
  Catalog views hit a further restriction: a non-admin can only transfer *view* ownership to a
  group, not directly to a user or service principal. For those, the fix was simpler than
  working around the restriction: drop the view (it's just a saved query, no data lives in it)
  and let the job recreate it, which makes the service principal the owner from the start.

## What this demonstrates

- dbt-databricks depth beyond a bare staging-to-marts pipeline: a real incremental Delta-merge
  model, an SCD2 snapshot, seeds versus sources, custom test macros, generated docs
- A native `dbt_task` inside a Lakeflow Job, deployed via a Databricks Asset Bundle, not dbt
  Cloud, not a notebook running `!dbt run`
- Real analytics-engineering judgment: correctly modeling customer identity
  (`customer_unique_id`), catching a test that only *looked* correct, and deciding when a real
  data-quality gap is a tolerance to document versus a bug to fix
- Terraform reused and extended safely across two repos sharing infrastructure, where Unity
  Catalog grants can't just be copy-pasted once two states touch the same catalog
- A CI/CD pipeline that genuinely deploys to staging before production, over the same
  mechanism for both, including finding and fixing the platform-permission gaps that only show
  up once a real deploy actually runs
