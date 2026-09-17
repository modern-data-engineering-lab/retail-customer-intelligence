# Terraform — platform layer for retail-customer-intelligence

Provisions this repo's own slice of the shared Databricks Free Edition workspace: a schema
inside the existing `staging_catalog`/`prod_catalog` (provisioned by
`databricks-bundle-template`'s Terraform, not this repo's), a volume for the raw Olist CSVs,
two service principals + their OAuth secrets, schema-level grants, SQL warehouse access, and
GitHub `staging`/`production` environments with branch-restricted deployment policies.

## Why this repo doesn't own the catalogs

`databricks-bundle-template` already provisioned `staging_catalog`/`prod_catalog`, and this
repo deliberately reuses them rather than standing up new ones — Unity Catalog catalogs are
the natural environment boundary on a single Free Edition workspace, and there's no reason
every repo needs its own pair. But `databricks_grants` is authoritative for the *entire* grant
list of whatever it targets: if this repo also declared `databricks_grants` on
`staging_catalog`, its Terraform state and the template's would each think they alone own that
catalog's grants, and every `apply` from either side would silently strip whatever the other
one had granted. So `databricks.tf` only *reads* the catalogs (`data "databricks_catalog"`)
and grants at the **schema** level instead, where this repo has sole ownership. The one thing
that can't be fully automated as a result: granting this repo's service principals `USE
CATALOG` on the shared catalog (needed just to traverse into it) has to happen once, manually,
outside Terraform — see `terraform apply`'s `manual_use_catalog_grant_commands` output below.
That output uses `databricks grants update` (the Grants REST API via the CLI), not a raw SQL
`GRANT` statement — it's an additive patch scoped to one principal rather than something that
risks reading as authoritative, and it needs no SQL warehouse running to execute. Confirmed
working: `databricks grants update catalog staging_catalog ... ` returned the full privilege
list afterward, `databricks-bundle-template`'s own `ALL_PRIVILEGES` grant on that catalog
untouched.

## Prerequisites

- Terraform >= 1.5.
- A Databricks CLI profile already authenticated (`databricks auth login --profile <name>`),
  or `DATABRICKS_HOST`/`DATABRICKS_TOKEN` (or client id/secret) exported as env vars.
- A GitHub token with repo admin + environment scope, exported as `GITHUB_TOKEN` — not the
  same as being logged into `gh` CLI.
- The ID of the existing shared SQL warehouse: `databricks warehouses list --profile
  weather-app`.

## Usage

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill in your own values, this file is gitignored
export GITHUB_TOKEN=<your-token>

terraform init
terraform plan    # read it before applying — it's creating real resources in a real workspace
terraform apply
```

After apply, run the two commands from the `manual_use_catalog_grant_commands` output — without
this, both service principals can see their own schema exists but can't actually reach it,
since `USE CATALOG` on the parent catalog isn't something this repo's Terraform is allowed to
grant (see above).

```bash
terraform output prod_service_principal_application_id
```
Paste this into `../databricks.yml`'s `prod` target under `run_as.service_principal_name` —
it needs the Application ID (a UUID), not the display name, same real gotcha
`databricks-bundle-template`'s README documents at length.

```bash
terraform output staging_raw_volume_path
terraform output prod_raw_volume_path
```
Upload the 9 Olist CSVs to both (Databricks UI, or `databricks fs cp`).

```bash
terraform output warehouse_http_path
```
Goes into `DBT_WAREHOUSE_HTTP_PATH` (GitHub secret, and `dbt/profiles/profiles.yml.example`
locally).

Then set the GitHub secrets (unless you enabled `manage_github_secrets_with_terraform`) — same
six as `databricks-bundle-template`, plus `DBT_WAREHOUSE_HTTP_PATH` in each environment.

## State

No remote backend — local `terraform.tfstate` (gitignored, never commit it: it holds the
service principal secrets in plaintext once applied). Same one-person/one-workspace tradeoff
as `databricks-bundle-template/terraform/README.md`.

## Destroying

```bash
terraform destroy
```
Only tears down this repo's own schema/volume/service principals/grants/GitHub environments —
it was never granted ownership of the shared catalogs, so there's no risk of a `destroy` here
taking `databricks-bundle-template`'s environment down with it.
