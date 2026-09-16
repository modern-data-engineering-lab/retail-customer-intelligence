variable "databricks_cli_profile" {
  description = <<-EOT
    Name of a `databricks auth login`-created CLI profile to authenticate as (see
    ~/.databrickscfg). Leave null to fall back to DATABRICKS_HOST/DATABRICKS_TOKEN or
    DATABRICKS_CLIENT_ID/DATABRICKS_CLIENT_SECRET environment variables instead.
  EOT
  type        = string
  default     = null
}

variable "github_owner" {
  description = "GitHub org or user that owns the repo (e.g. \"modern-data-engineering-lab\")."
  type        = string
}

variable "github_repository" {
  description = "Repository name only, no owner prefix (e.g. \"retail-customer-intelligence\")."
  type        = string
}

variable "staging_catalog_name" {
  description = <<-EOT
    The SHARED staging catalog already provisioned by databricks-bundle-template's Terraform —
    this repo only reads it (see databricks.tf's data source), it doesn't own it. Must match
    the `catalog` variable default for the `staging` target in ../databricks.yml.
  EOT
  type        = string
  default     = "staging_catalog"
}

variable "prod_catalog_name" {
  description = "The SHARED prod catalog — see staging_catalog_name. Must match ../databricks.yml's `prod` target."
  type        = string
  default     = "prod_catalog"
}

variable "schema_name" {
  description = <<-EOT
    This repo's own schema inside the shared catalog — the real isolation boundary now that
    more than one repo shares a catalog (see databricks.tf). Must match the `schema` variable
    default in ../resources/variables.yml.
  EOT
  type        = string
  default     = "retail_customer_intelligence"
}

variable "warehouse_id" {
  description = <<-EOT
    ID of the existing Free Edition SQL warehouse to grant this repo's service principals
    CAN_USE on (dbt_task and CI's `dbt build` both need it). Look it up with:
    `databricks warehouses list --profile weather-app`. No default — an empty/wrong warehouse
    ID fails loudly on apply rather than silently granting access to the wrong endpoint.
  EOT
  type        = string
}

variable "staging_service_principal_name" {
  description = "Display name for the staging service principal."
  type        = string
  default     = "sp-databricks-retail-customer-intelligence-staging"
}

variable "prod_service_principal_name" {
  description = "Display name for the prod service principal."
  type        = string
  default     = "sp-databricks-retail-customer-intelligence-prod"
}

variable "production_approver_github_user_id" {
  description = <<-EOT
    Numeric GitHub user ID (not username — get it with `gh api user -q .id`) required to
    approve a production deploy. Set to null to skip the required-reviewer gate entirely.
  EOT
  type        = number
  default     = null
}

variable "databricks_host" {
  description = <<-EOT
    Workspace URL (e.g. "https://dbc-xxxxxxxx-xxxx.cloud.databricks.com", no trailing slash
    or path). Only required if manage_github_secrets_with_terraform is true — it's what gets
    written as the DATABRICKS_HOST secret in both GitHub environments. Not used for
    Terraform's own Databricks auth (see databricks_cli_profile for that).
  EOT
  type        = string
  default     = null
}

variable "manage_github_secrets_with_terraform" {
  description = <<-EOT
    If true, Terraform writes DATABRICKS_HOST/CLIENT_ID/CLIENT_SECRET directly into the
    staging/production GitHub environment secrets. Convenient, but means the service
    principal secrets land in Terraform state in plaintext. Defaults to false: secrets stay a
    manual `gh secret set` step so state never holds a credential — same tradeoff as
    databricks-bundle-template/terraform/variables.tf.
  EOT
  type        = bool
  default     = false
}
